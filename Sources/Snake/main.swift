import CSDL3
import Foundation

private let PROFILER_TICK_GROUP = "TICK"
private let DEBUG_FONT_SIZE: Float = 10
private let CELL_SIZE: Int = 16
private let SPEW_MESSAGE_KEEP_SECONDS: Double = 3
private let MAX_SPEW_MESSAGES: Int = 25
private let SPEED_INCREASE_PER_FOOD: Double = 0.15
private let SPEED_UP_MODIFIER: Double = 1.8

@MainActor
private struct TextureSurfacePair: Resource {
    public var texture: SDLTexture
    public var surface: SDLSurface

    public static func loadBMP(
        sdl: SDL, renderer: SDLRenderer, from path: String, scale mode: SDLScaleMode = .NEAREST
    ) throws
        -> TextureSurfacePair
    {
        let surface = try sdl.loadBMP(from: path)
        let texture = try renderer.createTexture(from: surface)

        try texture.scaleMode(mode)

        return TextureSurfacePair(texture: texture, surface: surface)
    }

    public static func loadBMP(
        sdl: SDL, renderer: SDLRenderer, from memory: [UInt8], scale mode: SDLScaleMode = .NEAREST
    ) throws -> TextureSurfacePair {
        let surface = try sdl.loadBMP(from: memory)
        let texture = try renderer.createTexture(from: surface)

        try texture.scaleMode(mode)

        return TextureSurfacePair(texture: texture, surface: surface)
    }

    public func draw(
        render: SDLRenderer, x: Float, y: Float, scaleX: Float = 1.0, scaleY: Float = 1.0
    ) throws {
        let (width, height) = try self.size()

        try render.drawTexture(
            self.texture, dst: SDLFRect(x: x, y: y, w: width * scaleX, h: height * scaleY))
    }

    public func size() throws -> (w: Float, h: Float) {
        return try self.texture.size()
    }

    public mutating func destroy() {
        self.texture.destroy()
        self.surface.destroy()
    }
}

private enum Direction {
    case UP
    case DOWN
    case LEFT
    case RIGHT
}

private struct Snake: Sendable {
    public var head: (x: Int, y: Int) = (0, 0)
    public var body: [(x: Int, y: Int)] = []
}

private struct State: Sendable {
    public var speed: Double = 1
    public var score: Int = 0
    public var moveProgress: Double = 0
    public var direction: Direction = .RIGHT
    public var food: (x: Int, y: Int)? = nil
    public var snake: Snake = Snake()
}

private struct Keyboard: Sendable {
    private var _oldState: [Bool]
    private var _newState: [Bool]

    public init() {
        self._oldState = Array(repeating: false, count: Int(SDL_SCANCODE_COUNT.rawValue))
        self._newState = Array(repeating: false, count: Int(SDL_SCANCODE_COUNT.rawValue))
    }

    public mutating func update(new: [Bool]) {
        assert(new.count == SDL_SCANCODE_COUNT.rawValue)

        self._oldState = self._newState
        self._newState = new
    }

    public func isDown(_ key: SDL_Scancode) -> Bool {
        return self._newState[Int(key.rawValue)]
    }

    public func isAnyDown(_ keys: SDL_Scancode...) -> Bool {
        for key in keys {
            if self.isDown(key) {
                return true
            }
        }

        return false
    }

    public func wasPressed(_ key: SDL_Scancode) -> Bool {
        return !self._oldState[Int(key.rawValue)] && self.isDown(key)
    }

    public func wasAnyPressed(_ keys: SDL_Scancode...) -> Bool {
        for key in keys {
            if self.wasPressed(key) {
                return true
            }
        }

        return false
    }
}

private struct SpewMessage: Sendable {
    public let text: String
    public let spewAt: Double
}

@MainActor
private class App: Resource {
    // Handles
    private let _sdl: SDL
    private var _window: SDLWindow
    private var _renderer: SDLRenderer

    // Textures
    private var _bodyTexture: TextureSurfacePair! = nil
    private var _headTexture: TextureSurfacePair! = nil
    private var _foodTexture: TextureSurfacePair! = nil

    // Render info
    private var _viewport: SDLRect = SDLRect()

    // Game info
    private var _simulationTime: Double = 0
    private var _gameTime: Double = 0
    private var _grid: (x: Int, y: Int)!
    private var _state: State = State()
    private var _keyboard: Keyboard = Keyboard()
    private var _renderTime: Duration = .zero
    private var _printDebug: Bool = false
    private var _speedUp: Bool = false
    private var _gameOver: Bool = false
    private var _paused: Bool = false
    private var _quit: Bool = false
    private var _spewMessages: [SpewMessage] = []

    // Misc
    private var _profiler = Profiler()

    init() throws {
        self._sdl = try SDL.getInstance()
        self._window = try self._sdl.createWindow(
            title: "Snake", width: 600, height: 400, flags: [.OPENGL])
        self._renderer = try self._window.getRenderer()
    }

    public func run() {
        try! self.preload()

        while !self._quit {
            self._profiler.measure(PROFILER_TICK_GROUP) {
                try! self.tick(deltaTime: _renderTime.sec())
            }

            let sw = ContinuousClock()

            _renderTime = sw.measure {
                try! self.render()
            }
        }
    }

    private func spew(text: String) {
        if self._spewMessages.count >= MAX_SPEW_MESSAGES {
            self._spewMessages.removeFirst()
        }

        self._spewMessages.append(SpewMessage(text: text, spewAt: self._gameTime))
    }

    private func preload() throws {
        print("Preloading...")

        try self._renderer.vSync(true)

        self._viewport = try self._renderer.safeArea()
        self._grid = (self._viewport.w / CELL_SIZE, self._viewport.h / CELL_SIZE)

        print("Loading resources...")

        self._bodyTexture = try TextureSurfacePair.loadBMP(
            sdl: self._sdl, renderer: self._renderer, from: PackageResources.body_bmp)
        self._headTexture = try TextureSurfacePair.loadBMP(
            sdl: self._sdl, renderer: self._renderer, from: PackageResources.head_bmp)
        self._foodTexture = try TextureSurfacePair.loadBMP(
            sdl: self._sdl, renderer: self._renderer, from: PackageResources.food_bmp)

        print("Preload complete")
    }

    private func spawnFood() {
        var x: Int = 0
        var y: Int = 0

        repeat {
            x = Int.random(in: 0..<self._grid.x)
            y = Int.random(in: 0..<self._grid.y)
        } while self._state.snake.head == (x, y)

        self._state.food = (x, y)
    }

    private func tick(deltaTime: Double) throws {
        while true {
            guard let event = self._window.poll() else {
                break
            }

            if event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawValue
                || event.type == SDL_EVENT_QUIT.rawValue
            {
                self._quit = true

                return
            }
        }

        self._gameTime += deltaTime
        self._keyboard.update(new: try self._sdl.keyboardState())

        if self._keyboard.wasPressed(SDL_SCANCODE_ESCAPE) && !self._gameOver {
            self._paused = !self._paused
        }

        if self._keyboard.wasPressed(SDL_SCANCODE_F3) {
            self._printDebug = !self._printDebug
        }

        // Clean up spew messages

        self._spewMessages = self._spewMessages.filter {
            $0.spewAt + SPEW_MESSAGE_KEEP_SECONDS >= self._gameTime
        }

        if self._paused || self._gameOver {
            return
        }

        self._simulationTime += deltaTime

        // Game logic

        let movePart = { (from: (x: Int, y: Int), direction: Direction) in
            var newPos: (x: Int, y: Int) = (0, 0)

            switch direction {
            case .UP:
                newPos = (from.x, from.y - 1)
            case .DOWN:
                newPos = (from.x, from.y + 1)
            case .LEFT:
                newPos = (from.x - 1, from.y)
            case .RIGHT:
                newPos = (from.x + 1, from.y)
            }

            if newPos.x < 0 {
                newPos.x = self._grid.x - 1
            } else if newPos.x >= self._grid.x {
                newPos.x = 0
            } else if newPos.y < 0 {
                newPos.y = self._grid.y - 1
            } else if newPos.y >= self._grid.y {
                newPos.y = 0
            }

            return newPos
        }

        self._speedUp = self._keyboard.isDown(SDL_SCANCODE_LSHIFT)

        let firstBody = self._state.snake.body.first

        if self._keyboard.wasAnyPressed(SDL_SCANCODE_W, SDL_SCANCODE_UP)
            && (firstBody == nil || firstBody! != movePart(self._state.snake.head, .UP))
        {
            self._state.direction = .UP
        } else if self._keyboard.wasAnyPressed(SDL_SCANCODE_S, SDL_SCANCODE_DOWN)
            && (firstBody == nil || firstBody! != movePart(self._state.snake.head, .DOWN))
        {
            self._state.direction = .DOWN
        } else if self._keyboard.wasAnyPressed(SDL_SCANCODE_A, SDL_SCANCODE_LEFT)
            && (firstBody == nil || firstBody! != movePart(self._state.snake.head, .LEFT))
        {
            self._state.direction = .LEFT
        } else if self._keyboard.wasAnyPressed(SDL_SCANCODE_D, SDL_SCANCODE_RIGHT)
            && (firstBody == nil || firstBody! != movePart(self._state.snake.head, .RIGHT))
        {
            self._state.direction = .RIGHT
        }

        // Food collision

        if self._state.food != nil {
            if self._state.snake.head == self._state.food! {
                self.spew(text: "Food eaten")

                self._state.snake.body.append(self._state.snake.head)
                self._state.speed += SPEED_INCREASE_PER_FOOD
                self._state.food = nil
                self._state.score += 1
            }
        }

        // Snake move

        var speed = self._state.speed

        if self._speedUp {
            speed *= SPEED_UP_MODIFIER
        }

        self._state.moveProgress += speed * deltaTime

        if self._state.moveProgress >= 1.0 {
            var prevPos = self._state.snake.head

            self._state.moveProgress = 0
            self._state.snake.head = movePart(self._state.snake.head, self._state.direction)

            for (idx, bodyPart) in self._state.snake.body.enumerated() {
                if idx != self._state.snake.body.count - 1 && self._state.snake.head == bodyPart {
                    self._gameOver = true
                }

                if bodyPart == prevPos {
                    continue
                }

                self._state.snake.body[idx] = prevPos
                prevPos = bodyPart
            }
        }

        // Spawn food

        if self._state.food == nil {
            self.spawnFood()
        }
    }

    private func renderDebugInfo() throws {
        self._renderer.setDrawColor(.RGBA(255, 0, 255))

        let fps = 1000 / self._renderTime.ms()

        var posY: Float = DEBUG_FONT_SIZE
        let drawLine = { (text: String) in
            try self._renderer.drawDebugText(x: DEBUG_FONT_SIZE, y: posY, text: text)
            posY += DEBUG_FONT_SIZE
        }
        let skipLine = {
            posY += DEBUG_FONT_SIZE
        }

        try drawLine("* FRAME *")
        try drawLine(
            String(
                format: "Render time: %.1fms (%d FPS)", self._renderTime.ms(),
                fps.isNormal ? Int(fps) : 0
            ))
        try drawLine(String(format: "Game time: %.1fs", self._gameTime))
        try drawLine(String(format: "Simulation time: %.1fs", self._simulationTime))

        skipLine()
        try drawLine("* GAME *")

        try drawLine("Viewport: \(self._viewport.w)x\(self._viewport.h)")
        try drawLine("Grid: \(self._grid.x)x\(self._grid.y)")
        try drawLine(
            "Head: \(self._state.snake.head.x)x\(self._state.snake.head.y) -> \(self._state.direction)"
        )
        try drawLine("Body: \(self._state.snake.body.count)")
        try drawLine(String(format: "Speed: %.2f", self._state.speed))
        try drawLine(String(format: "Move progress: %.2f%", self._state.moveProgress))

        if self._state.food == nil {
            try drawLine("Food: None")
        } else {
            try drawLine(
                "Food: \(self._state.food!.x)x\(self._state.food!.y)")
        }

        skipLine()
        try drawLine("* PROFILER *")

        let tickGroup = self._profiler.group(PROFILER_TICK_GROUP)

        try drawLine(String(format: "Tick: %.3fms", tickGroup.avg().ms()))
    }

    private func renderSpew() throws {
        self._renderer.setDrawColor(.RGBA(250, 90, 220))

        for (idx, message) in self._spewMessages.enumerated() {
            try self._renderer.drawDebugText(
                x: Float(self._viewport.w) - Float(message.text.count) * DEBUG_FONT_SIZE,
                y: Float(idx) * DEBUG_FONT_SIZE + DEBUG_FONT_SIZE,
                text: message.text)
        }
    }

    private func render() throws {
        self._renderer.setDrawColor(.RGBA(0, 0, 0))
        self._renderer.clear()

        // World

        let snake = self._state.snake

        for bodyPart in snake.body {
            try self._bodyTexture.draw(
                render: self._renderer, x: Float(bodyPart.x * CELL_SIZE),
                y: Float(bodyPart.y * CELL_SIZE))
        }

        try self._headTexture.draw(
            render: self._renderer, x: Float(snake.head.x * CELL_SIZE),
            y: Float(snake.head.y * CELL_SIZE))

        if self._state.food != nil {
            try self._foodTexture.draw(
                render: self._renderer, x: Float(self._state.food!.x * CELL_SIZE),
                y: Float(self._state.food!.y * CELL_SIZE))
        }

        // Overlay

        let scoreText = "SCORE: \(self._state.score)"

        self._renderer.setDrawColor(.RGBA(255, 255, 255))
        try self._renderer.drawDebugText(
            x: Float(self._viewport.w) / 2 - Float(scoreText.count) * DEBUG_FONT_SIZE / 2,
            y: DEBUG_FONT_SIZE,
            text: scoreText
        )

        if self._paused && !self._gameOver {
            let text = "PAUSED"

            self._renderer.setDrawColor(.RGBA(247, 160, 3))
            try self._renderer.drawDebugText(
                x: Float(self._viewport.w) / 2 - Float(text.count) * DEBUG_FONT_SIZE / 2,
                y: Float(self._viewport.h) / 2 - DEBUG_FONT_SIZE / 2,
                text: text)
        }

        if self._gameOver {
            let text = "GAME OVER"

            self._renderer.setDrawColor(.RGBA(244, 50, 9))
            try self._renderer.drawDebugText(
                x: Float(self._viewport.w) / 2 - Float(text.count) * DEBUG_FONT_SIZE / 2,
                y: Float(self._viewport.h) / 2 - DEBUG_FONT_SIZE / 2,
                text: text
            )
        }

        if self._printDebug {
            try self.renderDebugInfo()
        }

        try self.renderSpew()

        self._renderer.present()
    }

    public func destroy() {
        self._bodyTexture?.destroy()
        self._headTexture?.destroy()
        self._foodTexture?.destroy()

        self._renderer.destroy()
        self._window.destroy()
    }
}

private var app = try! App()

app.run()
app.destroy()
