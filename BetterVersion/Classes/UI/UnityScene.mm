#import "UnityScene.h"
#import "UnityViewControllerBase.h"
#include "UnityAppController.h"
#include "Unity/UnityInterface.h"
#import "PluginBase/AppDelegateListener.h"

@implementation UnityScene {
    UIOpenURLContext *_pendingURLContext;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    ::printf("-> sceneDidBecomeActive()\n");
    auto appController = GetAppController();
    if ([appController respondsToSelector:@selector(applicationDidBecomeActive:)])
    {
        [appController applicationDidBecomeActive:UIApplication.sharedApplication];
    }
}

- (void)sceneWillResignActive:(UIScene *)scene {
    ::printf("-> sceneWillResignActive()\n");
    auto appController = GetAppController();
    if ([appController respondsToSelector:@selector(applicationWillResignActive:)])
    {
        [appController applicationWillResignActive:UIApplication.sharedApplication];
    }
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    ::printf("-> sceneWillEnterForeground()\n");
    auto appController = GetAppController();
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    [appController initUnityWithScene: windowScene];

    if (_pendingURLContext != nil)
    {
        [self applyURLContextAndNotify: _pendingURLContext];
        _pendingURLContext = nil;
    }

    if ([appController respondsToSelector:@selector(applicationWillEnterForeground:)])
    {
        [appController applicationWillEnterForeground:UIApplication.sharedApplication];
    }
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    ::printf("-> sceneDidEnterBackground()\n");
    auto appController = GetAppController();
    if ([appController respondsToSelector:@selector(applicationDidEnterBackground:)])
    {
        [appController applicationDidEnterBackground:UIApplication.sharedApplication];
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    UIOpenURLContext *ctx = [self firstValidContextFromContexts: URLContexts];

    if (ctx != nil)
        [self applyURLContextAndNotify: ctx];
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // Store first valid URL context for cold start; applied in sceneWillEnterForeground after Unity init.
    _pendingURLContext = [self firstValidContextFromContexts: connectionOptions.URLContexts];
}

- (UIOpenURLContext *)firstValidContextFromContexts:(NSSet<UIOpenURLContext *> *)contexts {
    for (UIOpenURLContext *ctx in contexts)
    {
        if (ctx.URL != nil && ctx.URL.absoluteString != nil)
            return ctx;
    }
    return nil;
}

- (void)applyURLContextAndNotify:(UIOpenURLContext *)ctx {
    if (ctx == nil || ctx.URL == nil)
        return;

    NSURL *url = ctx.URL;
    UnitySetAbsoluteURL(url.absoluteString.UTF8String);

    NSMutableDictionary<NSString*, id>* notifData = [NSMutableDictionary dictionaryWithCapacity: 3];
    notifData[@"url"] = url;
    if (ctx.options.sourceApplication != nil)
        notifData[@"sourceApplication"] = ctx.options.sourceApplication;
    if (ctx.options.annotation != nil)
        notifData[@"annotation"] = ctx.options.annotation;

    AppController_SendNotificationWithArg(kUnityOnOpenURL, notifData);
}
@end
