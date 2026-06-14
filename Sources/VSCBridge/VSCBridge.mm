// ObjC++ shim around the private (header-less) CoreGraphics virtual-display
// classes. Modeled on enfp-dev-studio/node-mac-virtual-display's virtual_display.mm.
// The classes ship in the public CoreGraphics binary; "private" only means
// Apple publishes no headers, so we declare the @interface ourselves.

#import "VSCBridge.h"

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>

#pragma mark - Private class declarations

@class CGVirtualDisplayDescriptor;
@class CGVirtualDisplay;

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) CGFloat refreshRate;
@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)w height:(NSUInteger)h refreshRate:(CGFloat)r;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) dispatch_queue_t dispatchQueue;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)d;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)s;
@end

#pragma mark - Helpers

static unsigned int vsc_djb2(const char *s) {
    unsigned long hash = 5381;
    if (!s) return (unsigned int)hash;
    for (; *s; ++s) hash = ((hash << 5) + hash) + (unsigned char)*s;
    return (unsigned int)(hash & 0xFFFFFFFF);
}

// Opaque handle holds a CFBridgingRetain'd CGVirtualDisplay* so ARC manages
// the retain count without __strong-in-struct quirks.
struct VSCDisplay {
    CFTypeRef bridged;  // CGVirtualDisplay*
};

#pragma mark - C API

VSCDisplayRef vsc_create(const VSCDisplayConfig *cfg, uint32_t *outDisplayID) {
    if (!cfg || cfg->width == 0 || cfg->height == 0) return NULL;

    NSString *name = [NSString stringWithUTF8String:cfg->name ?: "Virtual Display"];

    CGVirtualDisplayDescriptor *d = [[CGVirtualDisplayDescriptor alloc] init];
    d.name = name;
    d.maxPixelsWide = cfg->width;
    d.maxPixelsHigh = cfg->height;
    double mmPerPixel = 25.4 / (cfg->ppi > 0 ? cfg->ppi : 109.0);
    d.sizeInMillimeters = CGSizeMake(cfg->width * mmPerPixel, cfg->height * mmPerPixel);
    d.vendorID = 0xeeee;
    d.productID = (vsc_djb2([name UTF8String]) >> 16) & 0xFFFF;
    d.serialNum = vsc_djb2([name UTF8String]);
    d.dispatchQueue = dispatch_queue_create("com.vsc.virtualdisplay", DISPATCH_QUEUE_SERIAL);

    CGVirtualDisplay *vd = [[CGVirtualDisplay alloc] initWithDescriptor:d];
    if (!vd || vd.displayID == kCGNullDirectDisplay) return NULL;

    CGVirtualDisplaySettings *s = [[CGVirtualDisplaySettings alloc] init];
    s.hiDPI = cfg->hiDPI ? 1 : 0;
    CGVirtualDisplayMode *full =
        [[CGVirtualDisplayMode alloc] initWithWidth:cfg->width height:cfg->height refreshRate:cfg->refreshRate];
    if (cfg->hiDPI) {
        // Two modes (full + half) with hiDPI=1 => Retina backing
        // (logical resolution = half the physical resolution).
        CGVirtualDisplayMode *half = [[CGVirtualDisplayMode alloc]
            initWithWidth:cfg->width / 2 height:cfg->height / 2 refreshRate:cfg->refreshRate];
        s.modes = @[full, half];
    } else {
        s.modes = @[full];
    }
    [vd applySettings:s];

    // Headless / Screen-Sharing post-processing: keep the dummy an independent
    // extended display (not a mirror, not stealing main). Public CoreGraphics C API.
    uint32_t mainBefore = CGMainDisplayID();
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) == kCGErrorSuccess) {
        CGConfigureDisplayMirrorOfDisplay(config, vd.displayID, kCGNullDirectDisplay);
        if (CGMainDisplayID() == vd.displayID && vd.displayID != mainBefore) {
            CGConfigureDisplayOrigin(config, mainBefore, 0, 0);
        }
        CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    }

    if (outDisplayID) *outDisplayID = vd.displayID;

    struct VSCDisplay *box = (struct VSCDisplay *)calloc(1, sizeof(struct VSCDisplay));
    box->bridged = CFBridgingRetain(vd);
    return (VSCDisplayRef)box;
}

void vsc_destroy(VSCDisplayRef ref) {
    if (!ref) return;
    struct VSCDisplay *box = (struct VSCDisplay *)ref;
    if (box->bridged) {
        // nil the strong ref via the bridged release; the system tears the display down.
        CFBridgingRelease(box->bridged);
        box->bridged = NULL;
    }
    free(box);
}

uint32_t vsc_display_id(VSCDisplayRef ref) {
    if (!ref) return 0;
    struct VSCDisplay *box = (struct VSCDisplay *)ref;
    if (!box->bridged) return 0;
    CGVirtualDisplay *vd = (__bridge CGVirtualDisplay *)box->bridged;
    return vd.displayID;
}
