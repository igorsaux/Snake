import CSDL3

nonisolated(unsafe) weak private var _instance: SDL? = nil

public struct SDLError: Error, Sendable {
    public let message: String

    fileprivate static func current() -> SDLError {
        return SDLError(message: SDL.getError()!)
    }
}

public struct SDLFRect: Sendable {
    public let x: Float, y: Float, w: Float, h: Float

    public init(x: Float, y: Float, w: Float, h: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init(x: Float, y: Float, size: Float) {
        self.x = x
        self.y = y
        self.w = size
        self.h = size
    }

    public init() {
        self.x = 0
        self.y = 0
        self.w = 0
        self.h = 0
    }
}

public struct SDLRect: Sendable {
    public let x: Int, y: Int, w: Int, h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init() {
        self.x = 0
        self.y = 0
        self.w = 0
        self.h = 0
    }
}

public enum SDLScaleMode: Int32, Sendable {
    case NEAREST = 0
    case LINEAR = 1
}

@MainActor
public struct SDLTexture: Resource {
    fileprivate var handle: UnsafeMutablePointer<SDL_Texture>?

    fileprivate init(handle: UnsafeMutablePointer<SDL_Texture>) {
        self.handle = handle
    }

    public func scaleMode(_ mode: SDLScaleMode) throws {
        if !SDL_SetTextureScaleMode(self.handle, SDL_ScaleMode(mode.rawValue)) {
            throw SDLError.current()
        }
    }

    public func size() throws -> (w: Float, h: Float) {
        var w: Float = 0
        var h: Float = 0

        if !SDL_GetTextureSize(self.handle, &w, &h) {
            throw SDLError.current()
        }

        return (w, h)
    }

    public mutating func destroy() {
        assert(handle != nil)

        SDL_DestroyTexture(self.handle)
        self.handle = nil
    }
}

@MainActor
public struct SDLSurface: Resource {
    fileprivate var handle: UnsafeMutablePointer<SDL_Surface>?

    fileprivate init(handle: UnsafeMutablePointer<SDL_Surface>) {
        self.handle = handle
    }

    public mutating func destroy() {
        assert(handle != nil)

        SDL_DestroySurface(handle)
        self.handle = nil
    }
}

@MainActor
public struct SDLRenderer: Resource {
    fileprivate var handle: OpaquePointer?

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    public func safeArea() throws -> SDLRect {
        var rect = SDL_Rect()

        if !SDL_GetRenderSafeArea(self.handle, &rect) {
            throw SDLError.current()
        }

        return SDLRect(x: Int(rect.x), y: Int(rect.y), w: Int(rect.w), h: Int(rect.h))
    }

    public func clear() {
        SDL_RenderClear(self.handle)
    }

    public func createTexture(from surface: SDLSurface) throws -> SDLTexture {
        guard let handle = SDL_CreateTextureFromSurface(self.handle, surface.handle) else {
            throw SDLError.current()
        }

        return SDLTexture(handle: handle)
    }

    public func vSync(_ state: Bool) throws {
        if !SDL_SetRenderVSync(self.handle, state ? 1 : 0) {
            throw SDLError.current()
        }
    }

    public func setDrawColor(_ color: Color) {
        switch color {
        case .RGBA(let r, let g, let b, let a):
            SDL_SetRenderDrawColor(self.handle, r, g, b, a)
        }
    }

    public func drawDebugText(x: Float, y: Float, text: String) throws {
        if !SDL_RenderDebugText(self.handle, x, y, text) {
            throw SDLError.current()
        }
    }

    public func drawTexture(_ texture: SDLTexture, dst: SDLFRect?, src: SDLFRect? = nil) throws {
        let srcRect =
            src == nil ? SDL_FRect() : SDL_FRect(x: src!.x, y: src!.y, w: src!.w, h: src!.h)
        let dstRect =
            dst == nil ? SDL_FRect() : SDL_FRect(x: dst!.x, y: dst!.y, w: dst!.w, h: dst!.h)

        try withUnsafePointer(to: srcRect) { srcPtr in
            try withUnsafePointer(to: dstRect) { dstPtr in
                guard
                    SDL_RenderTexture(
                        self.handle, texture.handle, src == nil ? nil : srcPtr,
                        dst == nil ? nil : dstPtr) == true
                else {
                    throw SDLError.current()
                }
            }
        }
    }

    public func present() {
        SDL_RenderPresent(self.handle)
    }

    public mutating func destroy() {
        assert(self.handle != nil)

        SDL_DestroyRenderer(handle)
        self.handle = nil
    }
}

public struct SDLWindowFlags: Sendable, OptionSet, SetAlgebra {
    public let rawValue: Uint64

    public init(rawValue: Uint64) {
        self.rawValue = rawValue
    }

    public static let FULLSCREEN = SDLWindowFlags(rawValue: 0x0000_0000_0000_0001)
    public static let OPENGL = SDLWindowFlags(rawValue: 0x0000_0000_0000_0002)
    public static let OCCLUDED = SDLWindowFlags(rawValue: 0x0000_0000_0000_0004)
    public static let HIDDEN = SDLWindowFlags(rawValue: 0x0000_0000_0000_0008)
    public static let BORDERLESS = SDLWindowFlags(rawValue: 0x0000_0000_0000_0010)
    public static let RESIZABLE = SDLWindowFlags(rawValue: 0x0000_0000_0000_0020)
    public static let MINIMIZED = SDLWindowFlags(rawValue: 0x0000_0000_0000_0040)
    public static let MAXIMIZED = SDLWindowFlags(rawValue: 0x0000_0000_0000_0080)
    public static let MOUSE_GRABBED = SDLWindowFlags(rawValue: 0x0000_0000_0000_0100)
    public static let INPUT_FOCUS = SDLWindowFlags(rawValue: 0x0000_0000_0000_0200)
    public static let MOUSE_FOCUS = SDLWindowFlags(rawValue: 0x0000_0000_0000_0400)
    public static let EXTERNAL = SDLWindowFlags(rawValue: 0x0000_0000_0000_0800)
    public static let MODAL = SDLWindowFlags(rawValue: 0x0000_0000_0000_1000)
    public static let HIGH_PIXEL_DENSITY = SDLWindowFlags(rawValue: 0x0000_0000_0000_2000)
    public static let MOUSE_CAPTURE = SDLWindowFlags(rawValue: 0x0000_0000_0000_4000)
    public static let MOUSE_RELATIVE_MODE = SDLWindowFlags(rawValue: 0x0000_0000_0000_8000)
    public static let ALWAYS_ON_TOP = SDLWindowFlags(rawValue: 0x0000_0000_0001_0000)
    public static let UTILITY = SDLWindowFlags(rawValue: 0x0000_0000_0002_0000)
    public static let TOOLTIP = SDLWindowFlags(rawValue: 0x0000_0000_0004_0000)
    public static let POPUP_MENU = SDLWindowFlags(rawValue: 0x0000_0000_0008_0000)
    public static let KEYBOARD_GRABBED = SDLWindowFlags(rawValue: 0x0000_0000_0010_0000)
    public static let VULKAN = SDLWindowFlags(rawValue: 0x0000_0000_1000_0000)
    public static let METAL = SDLWindowFlags(rawValue: 0x0000_0000_2000_0000)
    public static let TRANSPARENT = SDLWindowFlags(rawValue: 0x0000_0000_4000_0000)
    public static let NOT_FOCUSABLE = SDLWindowFlags(rawValue: 0x0000_0000_8000_0000)
}

@MainActor
public struct SDLWindow: Resource {
    fileprivate var handle: OpaquePointer? = nil
    private var _renderer: SDLRenderer? = nil

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    public func poll() -> SDL_Event? {
        var ev = SDL_Event()

        if !SDL_PollEvent(&ev) {
            return nil
        }

        return ev
    }

    public mutating func getRenderer() throws -> SDLRenderer {
        if self._renderer == nil {
            guard let handle = SDL_CreateRenderer(self.handle!, nil) else {
                throw SDLError.current()
            }

            self._renderer = SDLRenderer(handle: handle)
        }

        return self._renderer!
    }

    public mutating func destroy() {
        assert(self.handle != nil)

        SDL_DestroyWindow(self.handle)
        self.handle = nil
    }
}

public final class SDL: Sendable {
    public static func getInstance() throws -> SDL {
        var newInstance = _instance

        if _instance == nil {
            if !SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) {
                throw SDLError.current()
            }

            newInstance = SDL()
            _instance = newInstance
        }

        return newInstance!
    }

    fileprivate static func getError() -> String? {
        guard let ptr = SDL_GetError() else {
            return nil
        }

        return String(cString: ptr)
    }

    @MainActor
    public func createWindow(title: String, width: Int32, height: Int32, flags: SDLWindowFlags)
        throws -> SDLWindow
    {
        guard
            let handle = SDL_CreateWindow(
                title, width, height, flags.rawValue
            )
        else {
            throw SDLError.current()
        }

        return SDLWindow(handle: handle)
    }

    @MainActor
    public func loadBMP(from path: String) throws -> SDLSurface {
        guard let surface = SDL_LoadBMP(path) else {
            throw SDLError.current()
        }

        return SDLSurface(handle: surface)
    }

    @MainActor
    public func loadBMP(from memory: [UInt8]) throws -> SDLSurface {
        try memory.withUnsafeBufferPointer { ptr in
            guard let io = SDL_IOFromConstMem(ptr.baseAddress, ptr.count) else {
                throw SDLError.current()
            }

            guard let surface = SDL_LoadBMP_IO(io, true) else {
                throw SDLError.current()
            }

            return SDLSurface(handle: surface)
        }
    }

    @MainActor
    public func keyboardState() throws -> [Bool] {
        var count: Int32 = 0

        guard let start = SDL_GetKeyboardState(&count) else {
            throw SDLError.current()
        }

        let buffer = UnsafeBufferPointer(start: start, count: Int(count))

        return Array(buffer)
    }

    deinit {
        SDL_Quit()
    }
}
