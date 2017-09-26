//
//  JGProgressHUD.m
//  JGProgressHUD
//
//  Created by Jonas Gessner on 20.7.14.
//  Copyright (c) 2014 Jonas Gessner. All rights reserved.
//

#import "JGProgressHUD.h"
#import <QuartzCore/QuartzCore.h>
#import "JGProgressHUDFadeAnimation.h"
#import "JGProgressHUDIndeterminateIndicatorView.h"

#if !__has_feature(objc_arc)
#error "JGProgressHUD requires ARC!"
#endif

static CGRect JGProgressHUD_CGRectIntegral(CGRect rect) {
    CGFloat scale = [[UIScreen mainScreen] scale];
    
    return (CGRect){{((CGFloat)floor(rect.origin.x*scale))/scale, ((CGFloat)floor(rect.origin.y*scale))/scale}, {((CGFloat)ceil(rect.size.width*scale))/scale, ((CGFloat)ceil(rect.size.height*scale))/scale}};
}

@interface JGProgressHUD () {
    BOOL _transitioning;
    BOOL _updateAfterAppear;
    
    BOOL _dismissAfterTransitionFinished;
    BOOL _dismissAfterTransitionFinishedWithAnimation;
    
    CFAbsoluteTime _displayTimestamp;
    
    JGProgressHUDIndicatorView *__nullable _indicatorViewAfterTransitioning;
    
    UIView *__nonnull _blurViewContainer;
}

@property (nonatomic, strong, readonly, nonnull) UIVisualEffectView *blurView;

@end

@interface JGProgressHUDAnimation (Private)

@property (nonatomic, weak, nullable) JGProgressHUD *progressHUD;

@end

@implementation JGProgressHUD

@synthesize HUDView = _HUDView;
@synthesize blurView = _blurView;
@synthesize textLabel = _textLabel;
@synthesize detailTextLabel = _detailTextLabel;
@synthesize indicatorView = _indicatorView;
@synthesize animation = _animation;
@synthesize contentView = _contentView;

@dynamic visible;

#pragma mark - Keyboard

static CGRect keyboardFrame = (CGRect){{0.0f, 0.0f}, {0.0f, 0.0f}};

+ (void)keyboardFrameWillChange:(NSNotification *)notification {
    keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (CGRectIsEmpty(keyboardFrame)) {
        keyboardFrame = [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    }
}

+ (void)keyboardFrameDidChange:(NSNotification *)notification {
    keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
}

+ (void)keyboardDidHide {
    keyboardFrame = CGRectZero;
}

+ (CGRect)currentKeyboardFrame {
    return keyboardFrame;
}

+ (void)load {
    [super load];
    
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameDidChange:) name:UIKeyboardDidChangeFrameNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidHide) name:UIKeyboardDidHideNotification object:nil];
    }
}

#pragma mark - Initializers

- (instancetype)init {
    return [self initWithStyle:JGProgressHUDStyleExtraLight];
}

- (instancetype)initWithFrame:(CGRect __unused)frame {
    return [self initWithStyle:JGProgressHUDStyleExtraLight];
}

- (instancetype)initWithStyle:(JGProgressHUDStyle)style {
    self = [super initWithFrame:CGRectZero];
    
    if (self) {
        _style = style;
        _voiceOverEnabled = YES;
        
        _HUDView = [[UIView alloc] init];
        self.HUDView.backgroundColor = [UIColor clearColor];
        [self addSubview:self.HUDView];
        
        _blurViewContainer = [[UIView alloc] init];
        _blurViewContainer.backgroundColor = [UIColor clearColor];
        _blurViewContainer.clipsToBounds = YES;
        [self.HUDView addSubview:_blurViewContainer];
        
        _indicatorView = [[JGProgressHUDIndeterminateIndicatorView alloc] initWithHUDStyle:self.style];
        
        self.hidden = YES;
        self.backgroundColor = [UIColor clearColor];

        self.contentInsets = UIEdgeInsetsMake(20.0, 20.0, 20.0, 20.0);
        self.layoutMargins = UIEdgeInsetsMake(20.0, 20.0, 20.0, 20.0);

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
        
        self.cornerRadius = 10.0f;
    }
    
    return self;
}

+ (instancetype)progressHUDWithStyle:(JGProgressHUDStyle)style {
    return [(JGProgressHUD *)[self alloc] initWithStyle:style];
}

#pragma mark - Layout

- (void)setHUDViewFrameCenterWithSize:(CGSize)size insetViewFrame:(CGRect)viewFrame {
    CGRect frame = (CGRect){CGPointZero, size};
    
    switch (self.position) {
        case JGProgressHUDPositionTopLeft:
            frame.origin.x = CGRectGetMinX(viewFrame);
            frame.origin.y = CGRectGetMinY(viewFrame);
            break;
            
        case JGProgressHUDPositionTopCenter:
            frame.origin.x = CGRectGetMidX(viewFrame) - size.width/2.0f;
            frame.origin.y = CGRectGetMinY(viewFrame);
            break;
            
        case JGProgressHUDPositionTopRight:
            frame.origin.x = CGRectGetMaxX(viewFrame) - size.width;
            frame.origin.y = CGRectGetMinY(viewFrame);
            break;
            
        case JGProgressHUDPositionCenterLeft:
            frame.origin.x = CGRectGetMinX(viewFrame);
            frame.origin.y = CGRectGetMidY(viewFrame) - size.height/2.0f;
            break;
            
        case JGProgressHUDPositionCenter:
            frame.origin.x = CGRectGetMidX(viewFrame) - size.width/2.0f;
            frame.origin.y = CGRectGetMidY(viewFrame) - size.height/2.0f;
            break;
            
        case JGProgressHUDPositionCenterRight:
            frame.origin.x = CGRectGetMaxX(viewFrame) - frame.size.width;
            frame.origin.y = CGRectGetMidY(viewFrame) - size.height/2.0f;
            break;
            
        case JGProgressHUDPositionBottomLeft:
            frame.origin.x = CGRectGetMinX(viewFrame);
            frame.origin.y = CGRectGetMaxY(viewFrame) - size.height;
            break;
            
        case JGProgressHUDPositionBottomCenter:
            frame.origin.x = CGRectGetMidX(viewFrame) - size.width/2.0f;
            frame.origin.y = CGRectGetMaxY(viewFrame) - frame.size.height;
            break;
            
        case JGProgressHUDPositionBottomRight:
            frame.origin.x = CGRectGetMaxX(viewFrame) - size.width;
            frame.origin.y = CGRectGetMaxY(viewFrame) - size.height;
            break;
    }
    
    CGRect oldHUDFrame = self.HUDView.frame;
    CGRect updatedHUDFrame = JGProgressHUD_CGRectIntegral(frame);
    
    self.HUDView.frame = updatedHUDFrame;
    _blurViewContainer.frame = self.HUDView.bounds;
    self.blurView.frame = self.HUDView.bounds;
    
    [UIView performWithoutAnimation:^{
        self.contentView.frame = (CGRect){{(oldHUDFrame.size.width - updatedHUDFrame.size.width)/2.0, (oldHUDFrame.size.height - updatedHUDFrame.size.height)/2.0}, updatedHUDFrame.size};
    }];
    
    self.contentView.frame = self.HUDView.bounds;
}

- (void)layoutHUD {
    if (_transitioning) {
        _updateAfterAppear = YES;
        return;
    }
    
    if (self.superview == nil) {
        return;
    }
    
    CGRect indicatorFrame = self.indicatorView.frame;
    indicatorFrame.origin.y = self.contentInsets.top;
    
    CGRect insetFrame = [self insetFrameForView:self];
    
    CGFloat maxContentWidth = insetFrame.size.width - self.contentInsets.left - self.contentInsets.right;
    CGFloat maxContentHeight = insetFrame.size.height - self.contentInsets.top - self.contentInsets.bottom;
    
    CGRect labelFrame = CGRectZero;
    CGRect detailFrame = CGRectZero;
    
    CGFloat currentY = CGRectGetMaxY(indicatorFrame);
    if (!CGRectIsEmpty(indicatorFrame)) {
        currentY += 10.0;
    }
    
    if (_textLabel.text.length > 0) {
        _textLabel.preferredMaxLayoutWidth = maxContentWidth;

        CGSize neededSize = _textLabel.intrinsicContentSize;
        neededSize.height = MIN(neededSize.height, maxContentHeight);
        
        labelFrame.size = neededSize;
        labelFrame.origin.y = currentY;
        currentY = CGRectGetMaxY(labelFrame) + 10.0;
    }
    
    if (_detailTextLabel.text.length > 0) {
        _detailTextLabel.preferredMaxLayoutWidth = maxContentWidth;

        CGSize neededSize = _detailTextLabel.intrinsicContentSize;
        neededSize.height = MIN(neededSize.height, maxContentHeight);
        
        detailFrame.size = neededSize;
        detailFrame.origin.y = currentY;
    }
    
    CGSize size = CGSizeZero;
    
    CGFloat width = MIN(self.contentInsets.left + MAX(indicatorFrame.size.width, MAX(labelFrame.size.width, detailFrame.size.width)) + self.contentInsets.right, insetFrame.size.width);
    
    CGFloat height = MAX(CGRectGetMaxY(labelFrame), MAX(CGRectGetMaxY(detailFrame), CGRectGetMaxY(indicatorFrame))) + self.contentInsets.bottom;
    
    if (self.square) {
        CGFloat uniSize = MAX(width, height);
        
        size.width = uniSize;
        size.height = uniSize;
        
        CGFloat heightDelta = (uniSize-height)/2.0f;
        
        labelFrame.origin.y += heightDelta;
        detailFrame.origin.y += heightDelta;
        indicatorFrame.origin.y += heightDelta;
    }
    else {
        size.width = width;
        size.height = height;
    }
    
    CGPoint center = CGPointMake(size.width/2.0f, size.height/2.0f);
    
    indicatorFrame.origin.x = center.x - indicatorFrame.size.width/2.0f;
    labelFrame.origin.x = center.x - labelFrame.size.width/2.0f;
    detailFrame.origin.x = center.x - detailFrame.size.width/2.0f;

    [UIView performWithoutAnimation:^{
        self.indicatorView.frame = indicatorFrame;
        _textLabel.frame = JGProgressHUD_CGRectIntegral(labelFrame);
        _detailTextLabel.frame = JGProgressHUD_CGRectIntegral(detailFrame);
    }];
    
    [self setHUDViewFrameCenterWithSize:size insetViewFrame:insetFrame];
}

- (CGRect)insetFrameForView:(UIView *)view {
    CGRect localKeyboardFrame = [view convertRect:[[self class] currentKeyboardFrame] fromView:nil];
    CGRect frame = view.bounds;
    
    if (!CGRectIsEmpty(localKeyboardFrame) && CGRectIntersectsRect(frame, localKeyboardFrame)) {
        CGFloat keyboardMinY = CGRectGetMinY(localKeyboardFrame);
        
        if (@available(iOS 11, tvOS 11, *)) {
            if (self.insetsLayoutMarginsFromSafeArea) {
                // This makes sure that the bottom safe area inset is only respected when that area is not covered by the keyboard. When the keyboard covers the bottom area outside of the safe area it is not necessary to keep the bottom safe area insets part of the insets for the HUD.
                keyboardMinY += self.safeAreaInsets.bottom;
            }
        }
        
        frame.size.height = MAX(MIN(frame.size.height, keyboardMinY), 0.0);
    }
    
    return UIEdgeInsetsInsetRect(frame, view.layoutMargins);
}

- (void)applyCornerRadius {
    self.HUDView.layer.cornerRadius = self.cornerRadius;
    _blurViewContainer.layer.cornerRadius = self.cornerRadius;
}

#pragma mark - Showing

- (void)cleanUpAfterPresentation {
    self.hidden = NO;
    
    _transitioning = NO;
    // Correct timestamp to the current time for animated presentations:
    _displayTimestamp = CFAbsoluteTimeGetCurrent();
    
    if (_indicatorViewAfterTransitioning) {
        self.indicatorView = _indicatorViewAfterTransitioning;
        _indicatorViewAfterTransitioning = nil;
        _updateAfterAppear = NO;
    }
    else if (_updateAfterAppear) {
        [self layoutHUD];
        _updateAfterAppear = NO;
    }
    
    if ([self.delegate respondsToSelector:@selector(progressHUD:didPresentInView:)]){
        [self.delegate progressHUD:self didPresentInView:self.targetView];
    }
    
    if (_dismissAfterTransitionFinished) {
        [self dismissAnimated:_dismissAfterTransitionFinishedWithAnimation];
        _dismissAfterTransitionFinished = NO;
        _dismissAfterTransitionFinishedWithAnimation = NO;
    }
    else if (self.voiceOverEnabled && UIAccessibilityIsVoiceOverRunning()) {
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self);
    }
}

- (void)showInView:(UIView *)view {
    [self showInView:view animated:YES];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    [self layoutHUD];
}

- (void)showInView:(UIView *)view animated:(BOOL)animated {
    if (_transitioning) {
        return;
    }
    else if (self.targetView != nil) {
#if DEBUG
        NSLog(@"[Warning] The HUD is already visible! Ignoring.");
#endif
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(progressHUD:willPresentInView:)]) {
        [self.delegate progressHUD:self willPresentInView:view];
    }
    
    _targetView = view;
    [_targetView addSubview:self];
    
    self.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.frame = _targetView.bounds;
    
    [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:_targetView attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:_targetView attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:_targetView attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0.0].active = YES;
    [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:_targetView attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0.0].active = YES;
    
    [self layoutHUD];
    
    _transitioning = YES;
    
    _displayTimestamp = CFAbsoluteTimeGetCurrent();
    
    if (animated && self.animation != nil) {
        [self.animation show];
    }
    else {
        [self cleanUpAfterPresentation];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardFrameChanged:) name:UIKeyboardDidChangeFrameNotification object:nil];
}

#pragma mark - Dismissing

- (void)cleanUpAfterDismissal {
    self.hidden = YES;
    [self removeFromSuperview];
    
    [self removeObservers];
    
    _transitioning = NO;
    _dismissAfterTransitionFinished = NO;
    _dismissAfterTransitionFinishedWithAnimation = NO;
    
    __typeof(self.targetView) targetView = self.targetView;
    _targetView = nil;
    
    if ([self.delegate respondsToSelector:@selector(progressHUD:didDismissFromView:)]) {
        [self.delegate progressHUD:self didDismissFromView:targetView];
    }
}

- (void)dismiss {
    [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated {
    if (_transitioning) {
        _dismissAfterTransitionFinished = YES;
        _dismissAfterTransitionFinishedWithAnimation = animated;
        return;
    }
    
    if (self.targetView == nil) {
        return;
    }
    
    if (self.minimumDisplayTime > 0.0 && _displayTimestamp > 0.0) {
        CFAbsoluteTime displayedTime = CFAbsoluteTimeGetCurrent()-_displayTimestamp;
        
        if (displayedTime < self.minimumDisplayTime) {
            NSTimeInterval delta = self.minimumDisplayTime-displayedTime;
            
            [self dismissAfterDelay:delta animated:animated];
            
            return;
        }
    }
    
    if ([self.delegate respondsToSelector:@selector(progressHUD:willDismissFromView:)]) {
        [self.delegate progressHUD:self willDismissFromView:self.targetView];
    }
    
    _transitioning = YES;

    if (animated && self.animation) {
        [self.animation hide];
    }
    else {
        [self cleanUpAfterDismissal];
    }
}

- (void)dismissAfterDelay:(NSTimeInterval)delay {
    [self dismissAfterDelay:delay animated:YES];
}

- (void)dismissAfterDelay:(NSTimeInterval)delay animated:(BOOL)animated {
    __weak __typeof(self) weakSelf = self;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.visible) {
                [strongSelf dismissAnimated:animated];
            }
        }
    });
}

#pragma mark - Callbacks

- (void)tapped:(UITapGestureRecognizer *)t {
    if (CGRectContainsPoint(self.contentView.bounds, [t locationInView:self.contentView])) {
        if (self.tapOnHUDViewBlock != nil) {
            self.tapOnHUDViewBlock(self);
        }
    }
    else if (self.tapOutsideBlock != nil) {
        self.tapOutsideBlock(self);
    }
}

static UIViewAnimationOptions UIViewAnimationOptionsFromUIViewAnimationCurve(UIViewAnimationCurve curve) {
    UIViewAnimationOptions testOptions = UIViewAnimationCurveLinear << 16;
    
    if (testOptions != UIViewAnimationOptionCurveLinear) {
        NSLog(@"Unexpected implementation of UIViewAnimationOptionCurveLinear");
    }
    
    return (UIViewAnimationOptions)(curve << 16);
}

- (void)keyboardFrameChanged:(NSNotification *)notification {
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    
    [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionsFromUIViewAnimationCurve(curve) animations:^{
        [self layoutHUD];
    } completion:nil];
}

- (void)updateMotionOnHUDView {
    BOOL reduceMotionEnabled = UIAccessibilityIsReduceMotionEnabled();
    
    BOOL wantsParallax = ((self.parallaxMode == JGProgressHUDParallaxModeDevice && !reduceMotionEnabled) || self.parallaxMode == JGProgressHUDParallaxModeAlwaysOn);
    BOOL hasParallax = (self.HUDView.motionEffects.count > 0);
    
    if (wantsParallax == hasParallax) {
        return;
    }
    
    if (!wantsParallax) {
        self.HUDView.motionEffects = @[];
    }
    else {
        UIInterpolatingMotionEffect *x = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        
        CGFloat maxMovement = 20.0f;
        
        x.minimumRelativeValue = @(-maxMovement);
        x.maximumRelativeValue = @(maxMovement);
        
        UIInterpolatingMotionEffect *y = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
        
        y.minimumRelativeValue = @(-maxMovement);
        y.maximumRelativeValue = @(maxMovement);
        
        self.HUDView.motionEffects = @[x, y];
    }
}

- (void)animationDidFinish:(BOOL)presenting {
    if (presenting) {
        [self cleanUpAfterPresentation];
    }
    else {
        [self cleanUpAfterDismissal];
    }
}

#pragma mark - Getters

- (BOOL)isVisible {
    return (self.superview != nil);
}

- (UIVisualEffectView *)blurView {
    if (!_blurView) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateMotionOnHUDView) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
        
        UIBlurEffectStyle effect;
        
        if (self.style == JGProgressHUDStyleDark) {
            effect = UIBlurEffectStyleDark;
        }
        else if (self.style == JGProgressHUDStyleLight) {
            effect = UIBlurEffectStyleLight;
        }
        else {
            effect = UIBlurEffectStyleExtraLight;
        }
        
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:effect];
        
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        
        [self updateMotionOnHUDView];
        
        [_blurViewContainer addSubview:_blurView];
        
        if (self.indicatorView) {
            [self.contentView addSubview:self.indicatorView];
        }
        
        [self.contentView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    }
    
    return _blurView;
}

- (UIView *)contentView {
    if (_contentView == nil) {
        _contentView = [[UIView alloc] init];
        [self.blurView.contentView addSubview:_contentView];
    }
    
    return _contentView;
}

- (UILabel *)textLabel {
    if (!_textLabel) {
        _textLabel = [[UILabel alloc] init];
        _textLabel.backgroundColor = [UIColor clearColor];
        _textLabel.textColor = (self.style == JGProgressHUDStyleDark ? [UIColor whiteColor] : [UIColor blackColor]);
        _textLabel.textAlignment = NSTextAlignmentCenter;
        _textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        _textLabel.numberOfLines = 0;
        [_textLabel addObserver:self forKeyPath:@"attributedText" options:(NSKeyValueObservingOptions)kNilOptions context:NULL];
        [_textLabel addObserver:self forKeyPath:@"text" options:(NSKeyValueObservingOptions)kNilOptions context:NULL];
        [_textLabel addObserver:self forKeyPath:@"font" options:(NSKeyValueObservingOptions)kNilOptions context:NULL];
        _textLabel.isAccessibilityElement = YES;
        
        [self.contentView addSubview:_textLabel];
    }
    
    return _textLabel;
}

- (UILabel *)detailTextLabel {
    if (!_detailTextLabel) {
        _detailTextLabel = [[UILabel alloc] init];
        _detailTextLabel.backgroundColor = [UIColor clearColor];
        _detailTextLabel.textColor = (self.style == JGProgressHUDStyleDark ? [UIColor whiteColor] : [UIColor blackColor]);
        _detailTextLabel.textAlignment = NSTextAlignmentCenter;
        _detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        _detailTextLabel.numberOfLines = 0;
        [_detailTextLabel addObserver:self forKeyPath:@"attributedText" options:(NSKeyValueObservingOptions)kNilOptions context:NULL];
        [_detailTextLabel addObserver:self forKeyPath:@"text" options:(NSKeyValueObservingOptions)kNilOptions context:NULL];
        [_detailTextLabel addObserver:self forKeyPath:@"font" options:(NSKeyValueObservingOptions)kNilOptions context:NULL];
        _detailTextLabel.isAccessibilityElement = YES;
        
        [self.contentView addSubview:_detailTextLabel];
    }
    
    return _detailTextLabel;
}

- (JGProgressHUDAnimation *)animation {
    if (!_animation) {
        self.animation = [JGProgressHUDFadeAnimation animation];
    }
    
    return _animation;
}

#pragma mark - Setters

- (void)setCornerRadius:(CGFloat)cornerRadius {
    if (fequal(self.cornerRadius, cornerRadius)) {
        return;
    }
    
    _cornerRadius = cornerRadius;
    
    [self applyCornerRadius];
}

- (void)setShadow:(JGProgressHUDShadow *)shadow {
    _shadow = shadow;
    
    if (_shadow != nil) {
        self.HUDView.layer.shadowColor = _shadow.color.CGColor;
        self.HUDView.layer.shadowOffset = _shadow.offset;
        self.HUDView.layer.shadowOpacity = _shadow.opacity;
        self.HUDView.layer.shadowRadius = _shadow.radius;
    }
    else {
        self.HUDView.layer.shadowOffset = CGSizeZero;
        self.HUDView.layer.shadowOpacity = 0.0;
        self.HUDView.layer.shadowRadius = 0.0;
    }
}

- (void)setAnimation:(JGProgressHUDAnimation *)animation {
    if (_animation == animation) {
        return;
    }
    
    _animation.progressHUD = nil;
    
    _animation = animation;
    
    _animation.progressHUD = self;
}

- (void)setParallaxMode:(JGProgressHUDParallaxMode)parallaxMode {
    if (self.parallaxMode == parallaxMode) {
        return;
    }
    
    _parallaxMode = parallaxMode;
    
    [self updateMotionOnHUDView];
}

- (void)setPosition:(JGProgressHUDPosition)position {
    if (self.position == position) {
        return;
    }
    
    _position = position;
    [self layoutHUD];
}

- (void)setSquare:(BOOL)square {
    if (self.square == square) {
        return;
    }
    
    _square = square;
    
    [self layoutHUD];
}

- (void)setIndicatorView:(JGProgressHUDIndicatorView *)indicatorView {
    if (self.indicatorView == indicatorView) {
        return;
    }
    
    if (_transitioning) {
        _indicatorViewAfterTransitioning = indicatorView;
        return;
    }
    
    [_indicatorView removeFromSuperview];
    _indicatorView = indicatorView;
    
    if (self.indicatorView) {
        [self.contentView addSubview:self.indicatorView];
    }
    
    [self layoutHUD];
}

- (void)layoutMarginsDidChange {
    [super layoutMarginsDidChange];
    
    [self layoutHUD];
}

- (void)setMarginInsets:(UIEdgeInsets)marginInsets {
    [self setLayoutMargins:marginInsets];
}

- (UIEdgeInsets)marginInsets {
    return [self layoutMargins];
}

- (void)setContentInsets:(UIEdgeInsets)contentInsets {
    if (UIEdgeInsetsEqualToEdgeInsets(self.contentInsets, contentInsets)) {
        return;
    }
    
    _contentInsets = contentInsets;
    
    [self layoutHUD];
}

- (void)setProgress:(float)progress {
    [self setProgress:progress animated:NO];
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
    if (fequal(self.progress, progress)) {
        return;
    }
    
    _progress = progress;
    
    [self.indicatorView setProgress:progress animated:animated];
}

#pragma mark - Overrides

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.interactionType == JGProgressHUDInteractionTypeBlockNoTouches) {
        return nil;
    }
    else {
        UIView *view = [super hitTest:point withEvent:event];
        
        if (self.interactionType == JGProgressHUDInteractionTypeBlockAllTouches) {
            return view;
        }
        else if (self.interactionType == JGProgressHUDInteractionTypeBlockTouchesOnHUDView && view != self) {
            return view;
        }
        
        return nil;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == _textLabel || object == _detailTextLabel) {
        [self layoutHUD];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)dealloc {
    [self removeObservers];
    
    [_textLabel removeObserver:self forKeyPath:@"attributedText"];
    [_textLabel removeObserver:self forKeyPath:@"text"];
    [_textLabel removeObserver:self forKeyPath:@"font"];
    
    [_detailTextLabel removeObserver:self forKeyPath:@"attributedText"];
    [_detailTextLabel removeObserver:self forKeyPath:@"text"];
    [_detailTextLabel removeObserver:self forKeyPath:@"font"];
}

- (void)removeObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidChangeFrameNotification object:nil];
}

@end

@implementation JGProgressHUD (HUDManagement)

+ (NSArray *)allProgressHUDsInView:(UIView *)view {
    NSMutableArray *HUDs = [NSMutableArray array];
    
    for (UIView *v in view.subviews) {
        if ([v isKindOfClass:[JGProgressHUD class]]) {
            [HUDs addObject:v];
        }
    }
    
    return HUDs.copy;
}

+ (NSMutableArray *)_allProgressHUDsInViewHierarchy:(UIView *)view {
    NSMutableArray *HUDs = [NSMutableArray array];
    
    for (UIView *v in view.subviews) {
        if ([v isKindOfClass:[JGProgressHUD class]]) {
            [HUDs addObject:v];
        }
        else {
            [HUDs addObjectsFromArray:[self _allProgressHUDsInViewHierarchy:v]];
        }
    }
    
    return HUDs;
}

+ (NSArray *)allProgressHUDsInViewHierarchy:(UIView *)view {
    return [self _allProgressHUDsInViewHierarchy:view].copy;
}

@end

@implementation JGProgressHUD (Deprecated)

- (void)showInRect:(CGRect __unused)rect inView:(UIView *)view {
    [self showInView:view];
}

- (void)showInRect:(CGRect __unused)rect inView:(UIView *)view animated:(BOOL)animated {
    [self showInView:view animated:animated];
}

@end
