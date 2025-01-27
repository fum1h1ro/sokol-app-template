#include <TargetConditionals.h>
#if !TARGET_OS_IPHONE
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#else
#import <UIKit/UIKit.h>
#endif

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <CoreText/CoreText.h>
#include "osxentry.h"

#if __has_feature(objc_arc)
#define _SAPP_OBJC_RELEASE(obj) { obj = nil; }
#else
#define _SAPP_OBJC_RELEASE(obj) { [obj release]; obj = nil; }
#endif

#if !TARGET_OS_IPHONE
@interface SokolApp : NSApplication
@end
@interface SokolAppDelegate : NSObject<NSApplicationDelegate>
@end
@interface SokolWindowDelegate : NSObject<NSWindowDelegate>
@property (nonatomic, strong) NSTimer* timer;
@end
static NSWindow* window;
#else
@interface SokolAppDelegate : NSObject<UIApplicationDelegate>
@end
static UIWindow* window;
#endif
@interface SokolViewDelegate : NSObject<MTKViewDelegate>
@end
@interface SokolMTKView : MTKView
@end

static int width;
static int height;
static int sample_count;
static sg_pixel_format depth_format;
static const char* window_title;
static osx_init_func init_func;
static osx_frame_func frame_func;
static osx_shutdown_func shutdown_func;
static osx_key_func key_down_func;
static osx_key_func key_up_func;
static osx_char_func char_func;
static osx_mouse_btn_func mouse_btn_down_func;
static osx_mouse_btn_func mouse_btn_up_func;
static osx_mouse_pos_func mouse_pos_func;
static osx_mouse_wheel_func mouse_wheel_func;
static id window_delegate;
static id<MTLDevice> mtl_device;
static id mtk_view_delegate;
static MTKView* mtk_view;
#if TARGET_OS_IPHONE
static id mtk_view_controller;
#endif
// @note: redraw counter
static int needs_redraw_count;


#if !TARGET_OS_IPHONE
//------------------------------------------------------------------------------
@implementation SokolApp
// From http://cocoadev.com/index.pl?GameKeyboardHandlingAlmost
// This works around an AppKit bug, where key up events while holding
// down the command key don't get sent to the key window.
- (void)sendEvent:(NSEvent*) event {
    if ([event type] == NSEventTypeKeyUp && ([event modifierFlags] & NSEventModifierFlagCommand)) {
        [[self keyWindow] sendEvent:event];
    }
    else {
        [super sendEvent:event];
    }
}
@end
#endif

//------------------------------------------------------------------------------
@implementation SokolAppDelegate
#if !TARGET_OS_IPHONE
- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    (void)aNotification;
#else
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
#endif
    // window delegate and main window
    #if TARGET_OS_IPHONE
        CGRect mainScreenBounds = [[UIScreen mainScreen] bounds];
        window = [[UIWindow alloc] initWithFrame:mainScreenBounds];
        (void)window_delegate;
    #else
        window_delegate = [[SokolWindowDelegate alloc] init];
        const NSUInteger style =
            NSWindowStyleMaskTitled |
            NSWindowStyleMaskClosable |
            NSWindowStyleMaskMiniaturizable |
            NSWindowStyleMaskResizable;
        window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, width, height)
            styleMask:style
            backing:NSBackingStoreBuffered
            defer:NO];
        [window setTitle:[NSString stringWithUTF8String:window_title]];
        [window setAcceptsMouseMovedEvents:YES];
        [window center];
        [window setRestorable:YES];
        [window setDelegate:window_delegate];

        // @note: this is a hack to add a 'Quit' menu item to the app menu
        NSMenuItem* app_menu_item = [NSApp.mainMenu itemAtIndex:0];
        NSMenu* app_menu = [[NSMenu alloc] init];
        NSString* quit_title = @"Quit";
        NSMenuItem* quit_item = [[NSMenuItem alloc] initWithTitle:quit_title action:@selector(terminate:) keyEquivalent:@"q"];
        [app_menu addItem:quit_item];
        app_menu_item.submenu = app_menu;
    #endif

    // view delegate, MTKView and Metal device
    mtk_view_delegate = [[SokolViewDelegate alloc] init];
    mtl_device = MTLCreateSystemDefaultDevice();
    mtk_view = [[SokolMTKView alloc] init];
    mtk_view.enableSetNeedsDisplay = YES;
    [mtk_view setPreferredFramesPerSecond:60];
    [mtk_view setDelegate:mtk_view_delegate];
    [mtk_view setDevice: mtl_device];
    [mtk_view setColorPixelFormat:MTLPixelFormatBGRA8Unorm];
    switch (depth_format) {
        case SG_PIXELFORMAT_DEPTH_STENCIL:
            [mtk_view setDepthStencilPixelFormat:MTLPixelFormatDepth32Float_Stencil8];
            break;
        case SG_PIXELFORMAT_DEPTH:
            [mtk_view setDepthStencilPixelFormat:MTLPixelFormatDepth32Float];
            break;
        default:
            [mtk_view setDepthStencilPixelFormat:MTLPixelFormatInvalid];
            break;
    }
    [mtk_view setSampleCount:(NSUInteger)sample_count];
    #if !TARGET_OS_IPHONE
        [window setContentView:mtk_view];
        CGSize drawable_size = { (CGFloat) width, (CGFloat) height };
        [mtk_view setDrawableSize:drawable_size];
        [[mtk_view layer] setMagnificationFilter:kCAFilterNearest];
        NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
        [NSApp activateIgnoringOtherApps:YES];
        [window makeKeyAndOrderFront:nil];
    #else
        [mtk_view setContentScaleFactor:1.0f];
        [mtk_view setUserInteractionEnabled:YES];
        [mtk_view setMultipleTouchEnabled:YES];
        [window addSubview:mtk_view];
        mtk_view_controller = [[UIViewController<MTKViewDelegate> alloc] init];
        [mtk_view_controller setView:mtk_view];
        [window setRootViewController:mtk_view_controller];
        [window makeKeyAndVisible];
    #endif

    // call the init function
    init_func();
    osx_needs_redraw();
    #if TARGET_OS_IPHONE
        return YES;
    #endif
}

#if !TARGET_OS_IPHONE
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}
#endif
@end

//------------------------------------------------------------------------------
#if !TARGET_OS_IPHONE
@implementation SokolWindowDelegate
- (BOOL)windowShouldClose:(id)sender {
    (void)sender;
    shutdown_func();
    return YES;
}

- (void)windowDidResize:(NSNotification*)notification {
    (void)notification;
    // FIXME
}

- (void)windowDidMove:(NSNotification*)notification {
    (void)notification;
    // FIXME
}

- (void)windowDidMiniaturize:(NSNotification*)notification {
    (void)notification;
    // FIXME
}

- (void)windowDidDeminiaturize:(NSNotification*)notification {
    (void)notification;
    // FIXME
}

- (void)windowDidBecomeKey:(NSNotification*)notification {
    (void)notification;
    // FIXME
}

- (void)windowDidResignKey:(NSNotification*)notification {
    (void)notification;
    // FIXME
}
@end
#endif

//------------------------------------------------------------------------------
@implementation SokolViewDelegate

- (void)mtkView:(nonnull MTKView*)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
    // FIXME
}

- (void)drawInMTKView:(nonnull MTKView*)view {
    (void)view;
    @autoreleasepool {
        frame_func();
    }
    if (needs_redraw_count > 0) {
        if (--needs_redraw_count <= 0) {
            mtk_view.paused = YES;
        }
    }
}
@end

//------------------------------------------------------------------------------
@implementation SokolMTKView

- (BOOL) isOpaque {
    return YES;
}

#if !TARGET_OS_IPHONE
- (BOOL)canBecomeKeyView {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    (void)event;
    if (mouse_btn_down_func) {
        mouse_btn_down_func(0);
    }
}

- (void)mouseDragged:(NSEvent*)event {
    [self mouseMoved:event];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    if (mouse_btn_up_func) {
        mouse_btn_up_func(0);
    }
}

- (void)mouseMoved:(NSEvent*)event {
    if (mouse_pos_func) {
        const NSRect content_rect = [mtk_view frame];
        const NSPoint pos = [event locationInWindow];
        mouse_pos_func(pos.x, content_rect.size.height - pos.y);
    }
}

- (void)rightMouseDown:(NSEvent*)event {
    (void)event;
    if (mouse_btn_down_func) {
        mouse_btn_down_func(1);
    }
}

- (void)rightMouseDragged:(NSEvent*)event {
    [self mouseMoved:event];
}

- (void)rightMouseUp:(NSEvent*)event {
    (void)event;
    if (mouse_btn_up_func) {
        mouse_btn_up_func(1);
    }
}

+ (ModifierKey)modifierFlags:(NSEventModifierFlags)flags {
    ModifierKey result = ModifierKey::None;
    if (flags & NSEventModifierFlagShift) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Shift);
    }
    if (flags & NSEventModifierFlagCapsLock) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::CapsLock);
    }
    if (flags & NSEventModifierFlagShift) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Shift);
    }
    if (flags & NSEventModifierFlagControl) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Control);
    }
    if (flags & NSEventModifierFlagOption) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Option);
    }
    if (flags & NSEventModifierFlagCommand) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Command);
    }
    if (flags & NSEventModifierFlagNumericPad) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::NumericPad);
    }
    if (flags & NSEventModifierFlagHelp) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Help);
    }
    if (flags & NSEventModifierFlagFunction) {
        result = (ModifierKey)((uint32_t)result | (uint32_t)ModifierKey::Function);
    }
    return result;
}

- (void)keyDown:(NSEvent*)event {
    if (key_down_func) {
        key_down_func([event keyCode], [SokolMTKView modifierFlags:[event modifierFlags]]);
    }
    if (char_func) {
        const NSString* characters = [event characters];
        const NSUInteger length = [characters length];
        for (NSUInteger i = 0; i < length; i++) {
            const unichar codepoint = [characters characterAtIndex:i];
            if ((codepoint & 0xFF00) == 0xF700) {
                continue;
            }
            char_func(codepoint);
        }
    }
}

- (void)flagsChanged:(NSEvent*)event {
    if (key_up_func) {
        key_up_func([event keyCode], [SokolMTKView modifierFlags:[event modifierFlags]]);
    }
}

- (void)keyUp:(NSEvent*)event {
    if (key_up_func) {
        key_up_func([event keyCode], [SokolMTKView modifierFlags:[event modifierFlags]]);
    }
}

- (void)scrollWheel:(NSEvent*)event {
    if (mouse_wheel_func) {
        double dy = [event scrollingDeltaY];
        if ([event hasPreciseScrollingDeltas]) {
            dy *= 0.1;
        }
        mouse_wheel_func((float)dy);
    }
}
#endif
@end

//------------------------------------------------------------------------------
void osx_start(int w, int h, int smp_count, sg_pixel_format depth_fmt, const char* title, osx_init_func ifun, osx_frame_func ffun, osx_shutdown_func sfun) {
    assert((depth_fmt == SG_PIXELFORMAT_DEPTH_STENCIL) || (depth_fmt == SG_PIXELFORMAT_DEPTH) || (depth_fmt == SG_PIXELFORMAT_NONE));
    width = w;
    height = h;
    sample_count = smp_count;
    depth_format = depth_fmt;
    window_title = title;
    init_func = ifun;
    frame_func = ffun;
    shutdown_func = sfun;
    key_down_func = 0;
    key_up_func = 0;
    char_func = 0;
    mouse_btn_down_func = 0;
    mouse_btn_up_func = 0;
    mouse_pos_func = 0;
    mouse_wheel_func = 0;
    needs_redraw_count = 0;
    #if !TARGET_OS_IPHONE
    [SokolApp sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    id delg = [[SokolAppDelegate alloc] init];
    [NSApp setDelegate:delg];
    [NSApp run];
    #else
    @autoreleasepool {
        int argc = 0;
        char* argv[] = {};
        UIApplicationMain(argc, argv, nil, NSStringFromClass([SokolAppDelegate class]));
    }
    #endif
}

sg_environment osx_environment(void) {
    return (sg_environment) {
        .defaults = {
            .color_format = SG_PIXELFORMAT_BGRA8,
            .depth_format = depth_format,
            .sample_count = sample_count,
        },
        .metal = {
            .device = (__bridge const void*) mtl_device,
        }
    };
}

sg_swapchain osx_swapchain(void) {
    return (sg_swapchain) {
        .width = (int) [mtk_view drawableSize].width,
        .height = (int) [mtk_view drawableSize].height,
        .sample_count = sample_count,
        .color_format = SG_PIXELFORMAT_BGRA8,
        .depth_format = depth_format,
        .metal = {
            .current_drawable = (__bridge const void*) [mtk_view currentDrawable],
            .depth_stencil_texture = (__bridge const void*) [mtk_view depthStencilTexture],
            .msaa_color_texture = (__bridge const void*) [mtk_view multisampleColorTexture],
        }
    };
}

void osx_needs_redraw(void) {
    needs_redraw_count = 30;
    mtk_view.paused = NO;
    [mtk_view setPreferredFramesPerSecond:60];
    #if !TARGET_OS_IPHONE
    [mtk_view setNeedsDisplay:YES];
    #else
    [mtk_view setNeedsDisplay];
    #endif
}

const char* osx_find_font(const char* font_name) {
    @autoreleasepool {
        NSString* font_name_ns = [NSString stringWithUTF8String:font_name];
        CTFontRef fontRef = CTFontCreateWithName((CFStringRef)font_name_ns, 0.0, NULL);
        const char* result = nullptr;
        if (fontRef) {
            CFURLRef urlRef = (CFURLRef)CTFontCopyAttribute(fontRef, kCTFontURLAttribute);
            if (urlRef) {
                NSString* fontPath = [(__bridge NSURL*)urlRef path];
                NSLog(@"font path: %@", fontPath);
                CFRelease(urlRef);
                result = strdup([fontPath UTF8String]);
            }
            CFRelease(fontRef);
        }
        return result;
    }
}

/* return current MTKView drawable width */
int osx_width() {
    return (int) [mtk_view drawableSize].width;
}

/* return current MTKView drawable height */
int osx_height() {
    return (int) [mtk_view drawableSize].height;
}

/* register input callbacks */
void osx_key_down(osx_key_func fn) {
    key_down_func = fn;
}
void osx_key_up(osx_key_func fn) {
    key_up_func = fn;
}
void osx_char(osx_char_func fn) {
    char_func = fn;
}
void osx_mouse_btn_down(osx_mouse_btn_func fn) {
    mouse_btn_down_func = fn;
}
void osx_mouse_btn_up(osx_mouse_btn_func fn) {
    mouse_btn_up_func = fn;
}
void osx_mouse_pos(osx_mouse_pos_func fn) {
    mouse_pos_func = fn;
}
void osx_mouse_wheel(osx_mouse_wheel_func fn) {
    mouse_wheel_func = fn;
}

#if defined(__OBJC__)
id<MTLDevice> osx_mtl_device() {
    return mtl_device;
}
#endif
