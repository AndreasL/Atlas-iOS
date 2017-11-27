//
//  ATLUIMessageInputToolbar.m
//  Atlas
//
//  Created by Kevin Coleman on 9/18/14.
//  Copyright (c) 2015 Layer. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
#import "ATLMessageInputToolbar.h"
#import "ATLConstants.h"
#import "ATLMediaAttachment.h"
#import "ATLMessagingUtilities.h"
#import "UIView+ATLHelpers.h"

NSString *const ATLMessageInputToolbarDidChangeHeightNotification = @"ATLMessageInputToolbarDidChangeHeightNotification";

@interface ATLMessageInputToolbar () <UITextViewDelegate>

@property (nonatomic) NSArray *mediaAttachments;
@property (nonatomic, copy) NSAttributedString *attributedStringForMessageParts;
@property (nonatomic) UITextView *dummyTextView;
@property (nonatomic) CGFloat textViewMaxHeight;
@property (nonatomic) CGFloat textViewMinScrollHeight;
@property (nonatomic) CGFloat buttonCenterY;
@property (nonatomic) BOOL firstAppearance;
@property (nonatomic) BOOL prominentAction;
@property (nonatomic) UIView *simpleLine;
@property (nonatomic) UIView *overlayView;
@property (nonatomic) UIView *underlayView;

@end

@implementation ATLMessageInputToolbar

NSString *const ATLMessageInputToolbarAccessibilityLabel = @"Message Input Toolbar";
NSString *const ATLMessageInputToolbarTextInputView = @"Message Input Toolbar Text Input View";
NSString *const ATLMessageInputToolbarCameraButton  = @"Message Input Toolbar Camera Button";
NSString *const ATLMessageInputToolbarLocationButton  = @"Message Input Toolbar Location Button";
NSString *const ATLMessageInputToolbarSendButton  = @"Message Input Toolbar Send Button";

// Compose View Margin Constants
static CGFloat const ATLLeftButtonHorizontalMargin = 6.0f;
static CGFloat const ATLRightButtonHorizontalMargin = 6.0f;
static CGFloat const ATLTopVerticalMargin = 10.0f;
static CGFloat const ATLBottomVerticalMargin = 50.0f;
static CGFloat const ATLBottomVerticalMarginExtended = 84.0f;
static CGFloat const ATLSendButtonPlacementOffset = 16.0f;

// Compose View Button Constants
static CGFloat const ATLLeftAccessoryButtonWidth = 40.0f;
static CGFloat const ATLRightAccessoryButtonDefaultWidth = 46.0f;
static CGFloat const ATLRightAccessoryButtonPadding = 5.3f;
static CGFloat const ATLButtonHeight = 28.0f;

+ (void)initialize
{
    ATLMessageInputToolbar *proxy = [self appearance];
    proxy.rightAccessoryButtonActiveColor = ATLBlueColor();
    proxy.rightAccessoryButtonDisabledColor = [UIColor grayColor];
    proxy.rightAccessoryButtonFont = [UIFont boldSystemFontOfSize:17];
}

- (id)init
{
    self = [super init];
    if (self) {
        self.accessibilityLabel = ATLMessageInputToolbarAccessibilityLabel;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        NSBundle *resourcesBundle = ATLResourcesBundle();
        self.leftAccessoryImage = [UIImage imageNamed:@"camera_dark" inBundle:resourcesBundle compatibleWithTraitCollection:nil];
        self.rightAccessoryImage = [UIImage imageNamed:@"location_dark" inBundle:resourcesBundle compatibleWithTraitCollection:nil];
        self.displaysRightAccessoryImage = YES;
        self.firstAppearance = YES;
        self.simpleLine = [[UIView alloc] initWithFrame:CGRectMake(0, 45, [UIScreen mainScreen].bounds.size.width, 1)];

        self.overlayView = [[UIView alloc] initWithFrame:CGRectMake(0, self.actionButton.frame.origin.y+self.textInputView.frame.size.height-10, [UIScreen mainScreen].bounds.size.width, 1)];
        self.underlayView = [[UIView alloc] initWithFrame:CGRectMake(0, self.textInputView.frame.origin.y+self.textInputView.frame.size.height, [UIScreen mainScreen].bounds.size.width, 65)];
        self.underlayView.hidden = YES;
        [self addSubview:self.overlayView];
        [self addSubview:self.underlayView];
        [self addSubview:self.simpleLine];
        
        
        self.leftAccessoryButton = [[UIButton alloc] init];
        self.leftAccessoryButton.accessibilityLabel = ATLMessageInputToolbarCameraButton;
        self.leftAccessoryButton.contentMode = UIViewContentModeScaleAspectFit;
        [self.leftAccessoryButton setImage:self.leftAccessoryImage forState:UIControlStateNormal];
        [self.leftAccessoryButton addTarget:self action:@selector(leftAccessoryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.leftAccessoryButton];

        self.textInputView = [[ATLMessageComposeTextView alloc] init];
        self.textInputView.accessibilityLabel = ATLMessageInputToolbarTextInputView;
        self.textInputView.delegate = self;
        [self addSubview:self.textInputView];

        self.topVerticalMargin = ATLTopVerticalMargin;
        self.bottomVerticalMargin = ATLBottomVerticalMargin;
        self.sendButtonOffset = ATLSendButtonPlacementOffset;

        self.rightAccessoryButton = [[UIButton alloc] init];
        [self.rightAccessoryButton addTarget:self action:@selector(rightAccessoryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        self.rightAccessoryButtonTitle = @"Send";
        [self addSubview:self.rightAccessoryButton];
        [self configureRightAccessoryButtonState];

        self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.actionButton setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];
        [self.actionButton setTitleColor:UIColor.grayColor forState:UIControlStateHighlighted];
        [self.actionButton setTitle:nil forState:UIControlStateNormal];
        [self.actionButton.titleLabel setFont:[UIFont boldSystemFontOfSize:14.0f]];
        [self.actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.actionButton];
        
        self.statusLabel = [[UILabel alloc] init];
        self.statusLabel.text = nil;
        [self.statusLabel setFont:[UIFont boldSystemFontOfSize:14.0f]];
        self.statusLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:self.statusLabel];

        // Calling sizeThatFits: or contentSize on the displayed UITextView causes the cursor's position to momentarily appear out of place and prevent scrolling to the selected range. So we use another text view for height calculations.
        self.dummyTextView = [[ATLMessageComposeTextView alloc] init];
        self.maxNumberOfLines = 8;
        self.barTintColor = UIColor.whiteColor;
        
        // [self setActionButtonProminent:YES];
    }
    return self;
}

- (void)setActionButtonHidden:(BOOL)hidden
{
    if (hidden == YES) {
        self.bottomVerticalMargin = 7.0f;
        self.sendButtonOffset = 0.0f;
    } else {
        self.bottomVerticalMargin = ATLBottomVerticalMargin;
        self.sendButtonOffset = ATLSendButtonPlacementOffset;
    }

    [self layoutSubviews];
}

- (void)setActionButtonProminent:(BOOL)prominent
{
    if (prominent) {
        self.bottomVerticalMargin = ATLBottomVerticalMarginExtended;
        self.prominentAction = YES;
        self.statusLabel.hidden = YES;
        self.simpleLine.hidden = YES;
        self.underlayView.hidden = NO;
    } else {
        self.prominentAction = NO;
        self.statusLabel.hidden = NO;
        self.bottomVerticalMargin = ATLBottomVerticalMargin;
    }
    
    [self layoutSubviews];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    [self bringSubviewToFront:self.leftAccessoryButton];
    [self bringSubviewToFront:self.textInputView];
    [self bringSubviewToFront:self.rightAccessoryButton];
    [self bringSubviewToFront:self.actionButton];
    
    if (self.firstAppearance) {
        [self configureRightAccessoryButtonState];
        self.firstAppearance = NO;
    }
    
    UIEdgeInsets safeAreaInsets = [self atl_safeAreaInsets];
    
    // set the font for the dummy text view as well
    self.dummyTextView.font = self.textInputView.font;

    // We layout the views manually since using Auto Layout seems to cause issues in this context (i.e. an auto height resizing text view in an input accessory view) especially with iOS 7.1.
    CGRect frame = self.frame;
    CGRect leftButtonFrame = self.leftAccessoryButton.frame;
    CGRect rightButtonFrame = self.rightAccessoryButton.frame;
    CGRect textViewFrame = self.textInputView.frame;

    if (!self.leftAccessoryButton) {
        leftButtonFrame.size.width = 0;
    } else {
        leftButtonFrame.size.width = ATLLeftAccessoryButtonWidth;
    }

    // This makes the input accessory view work with UISplitViewController to manage the frame width.
    if (self.containerViewController) {
        CGRect windowRect = [self.containerViewController.view.superview convertRect:self.containerViewController.view.frame toView:nil];
        frame.size.width = windowRect.size.width;
        frame.origin.x = windowRect.origin.x;
    }

    leftButtonFrame.size.height = ATLButtonHeight;
    leftButtonFrame.origin.x = ATLLeftButtonHorizontalMargin + safeAreaInsets.left;

    if (self.rightAccessoryButtonFont && (self.textInputView.text.length || !self.displaysRightAccessoryImage)) {
        rightButtonFrame.size.width = CGRectIntegral([ATLLocalizedString(@"atl.messagetoolbar.send.key", self.rightAccessoryButtonTitle, nil) boundingRectWithSize:CGSizeMake(MAXFLOAT, MAXFLOAT) options:0 attributes:@{NSFontAttributeName: self.rightAccessoryButtonFont} context:nil]).size.width + ATLRightAccessoryButtonPadding;
    } else {
        rightButtonFrame.size.width = ATLRightAccessoryButtonDefaultWidth;
    }

    rightButtonFrame.size.height = ATLButtonHeight;
    rightButtonFrame.origin.x = CGRectGetWidth(frame) - CGRectGetWidth(rightButtonFrame) -
                                ATLRightButtonHorizontalMargin - safeAreaInsets.right;

    textViewFrame.origin.x = CGRectGetMaxX(leftButtonFrame) + ATLLeftButtonHorizontalMargin;
    textViewFrame.origin.y = self.topVerticalMargin;
    textViewFrame.size.width = CGRectGetMinX(rightButtonFrame) - CGRectGetMinX(textViewFrame) - ATLRightButtonHorizontalMargin;

    self.dummyTextView.attributedText = self.textInputView.attributedText;
    CGSize fittedTextViewSize = [self.dummyTextView sizeThatFits:CGSizeMake(CGRectGetWidth(textViewFrame), MAXFLOAT)];
    textViewFrame.size.height = ceil(MIN(fittedTextViewSize.height, self.textViewMaxHeight));

    frame.size.height = CGRectGetHeight(textViewFrame) + self.topVerticalMargin * 2 + safeAreaInsets.bottom;
    frame.origin.y -= frame.size.height - CGRectGetHeight(self.frame);

    // Only calculate button centerY once to anchor it to bottom of bar.
    if (!self.buttonCenterY) {
        self.buttonCenterY = (CGRectGetHeight(frame) - CGRectGetHeight(leftButtonFrame)) / 2;
    }
    leftButtonFrame.origin.y = frame.size.height - leftButtonFrame.size.height - self.buttonCenterY - safeAreaInsets.bottom;
    rightButtonFrame.origin.y = frame.size.height - rightButtonFrame.size.height - self.buttonCenterY - safeAreaInsets.bottom;
    
    BOOL heightChanged = CGRectGetHeight(textViewFrame) != CGRectGetHeight(self.textInputView.frame);

    self.leftAccessoryButton.frame = leftButtonFrame;
    self.rightAccessoryButton.frame = rightButtonFrame;
    self.textInputView.frame = textViewFrame;

    self.statusLabel.frame = CGRectMake(ATLLeftButtonHorizontalMargin + 15.0f, 18.0f + self.textInputView.frame.origin.y + self.textInputView.frame.size.height, 202.0f, 22.0f);

    
    CGRect statusLabelFrame = self.statusLabel.frame;
    statusLabelFrame.origin.x = CGRectGetWidth(frame) - CGRectGetWidth(statusLabelFrame) - 15;
    self.statusLabel.frame = statusLabelFrame;
    
    // [self.statusLabel sizeToFit];
    [self.actionButton setTitleEdgeInsets:UIEdgeInsetsMake(0, 0, 0, 0)];
    self.actionButton.frame = CGRectMake(ATLLeftButtonHorizontalMargin + 10.0f, 16.0f + self.textInputView.frame.origin.y + self.textInputView.frame.size.height, 202.0f, 22.0f);
    [self.actionButton sizeToFit];
    
    if (self.prominentAction == YES) {
        [self bottomButtonSetup];
    } else{
        [self simpleLineSetup];
        
    }
    // Setting one's own frame like this is a no-no but seems to be the lesser of evils when working around the layout issues mentioned above.
    self.frame = frame;
    if (heightChanged) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ATLMessageInputToolbarDidChangeHeightNotification object:self];
    }
}
-(void)simpleLineSetup{
    self.simpleLine.frame = CGRectMake(0, self.textInputView.frame.size.height+20, [UIScreen mainScreen].bounds.size.width, 1);
    self.simpleLine.backgroundColor = [UIColor colorWithRed:0.87 green:0.87 blue:0.87 alpha:1.0];
    self.simpleLine.hidden = NO;
    self.simpleLine.alpha = 1.0f;
    self.simpleLine.layer.zPosition = 2;
    self.overlayView.alpha = 1.0f;
    self.underlayView.layer.zPosition = 1;
    self.underlayView.frame = CGRectMake(0, self.textInputView.frame.size.height+20, [UIScreen mainScreen].bounds.size.width, 40);
    self.underlayView.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.96 alpha:1.0];
    self.underlayView.hidden = NO;
    self.actionButton.layer.zPosition = 3;
    self.statusLabel.layer.zPosition = 3;
    [self bringSubviewToFront:self.actionButton];
}
-(void)bottomButtonSetup{
    self.overlayView.layer.zPosition = 2;
    self.underlayView.frame = CGRectMake(0, self.textInputView.frame.size.height+20, [UIScreen mainScreen].bounds.size.width, 80);
    self.overlayView.frame = CGRectMake(0, self.textInputView.frame.size.height+19, [UIScreen mainScreen].bounds.size.width, 1);
    self.underlayView.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.96 alpha:1.0];
    self.overlayView.backgroundColor = [UIColor colorWithRed:0.87 green:0.87 blue:0.87 alpha:1.0];
    self.underlayView.alpha = 1.0f;
    self.overlayView.alpha = 1.0f;
    self.underlayView.layer.zPosition = 1;
    self.actionButton.layer.zPosition = 3;
    [self bringSubviewToFront:self.actionButton];
    [self prominentButtonStyle];

}
-(void)prominentButtonStyle{
    // self.actionButton.frame = CGRectMake(self.actionButton.frame.origin.x, self.actionButton.frame.origin.y, self.actionButton.frame.size.width + 5.0f, 22.0f);
    // self.actionButton.frame = CGRectMake(ATLLeftButtonHorizontalMargin + 10.0f, 10.0f + self.textInputView.frame.origin.y + self.textInputView.frame.size.height, 202.0f, 22.0f);
    self.actionButton.frame = CGRectMake(self.actionButton.frame.origin.x, self.actionButton.frame.origin.y+7.0f, (self.frame.size.width - self.actionButton.frame.origin.x*2)-5, 50.0f);
    self.actionButton.layer.cornerRadius = 8.0f;
    self.actionButton.backgroundColor = [UIColor colorWithRed:104/255.0f green:59/255.0f blue:189/255.0f alpha:1.0f];
    [self.actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.actionButton setTitleColor:[UIColor colorWithRed:255/255.0f green:255/255.0f blue:255/255.0f alpha:0.7f]forState:UIControlStateHighlighted];
}
- (void)paste:(id)sender
{
    NSData *imageData = [[UIPasteboard generalPasteboard] dataForPasteboardType:ATLPasteboardImageKey];
    if (imageData) {
        UIImage *image = [UIImage imageWithData:imageData];
        ATLMediaAttachment *mediaAttachment = [ATLMediaAttachment mediaAttachmentWithImage:image
                                                                                  metadata:nil
                                                                             thumbnailSize:ATLDefaultThumbnailSize];
        [self insertMediaAttachment:mediaAttachment withEndLineBreak:YES];
    }
}

#pragma mark - Public Methods

- (void)setMaxNumberOfLines:(NSUInteger)maxNumberOfLines
{
    _maxNumberOfLines = maxNumberOfLines;
    self.textViewMaxHeight = self.maxNumberOfLines * self.textInputView.font.lineHeight;
    self.textViewMinScrollHeight = (self.maxNumberOfLines - 1) * self.textInputView.font.lineHeight;
    [self setNeedsLayout];
}

- (void)insertMediaAttachment:(ATLMediaAttachment *)mediaAttachment withEndLineBreak:(BOOL)endLineBreak;
{
    UITextView *textView = self.textInputView;

    NSMutableAttributedString *attributedString = [textView.attributedText mutableCopy];
    NSAttributedString *lineBreak = [[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: self.textInputView.font}];
    if (attributedString.length > 0 && ![textView.text hasSuffix:@"\n"]) {
        [attributedString appendAttributedString:lineBreak];
    }

    NSMutableAttributedString *attachmentString = (mediaAttachment.mediaMIMEType == ATLMIMETypeTextPlain) ? [[NSAttributedString alloc] initWithString:mediaAttachment.textRepresentation] : [[NSAttributedString attributedStringWithAttachment:mediaAttachment] mutableCopy];
    [attributedString appendAttributedString:attachmentString];
    if (endLineBreak) {
        [attributedString appendAttributedString:lineBreak];
    }
    [attributedString addAttribute:NSFontAttributeName value:textView.font range:NSMakeRange(0, attributedString.length)];
    if (textView.textColor) {
        [attributedString addAttribute:NSForegroundColorAttributeName value:textView.textColor range:NSMakeRange(0, attributedString.length)];
    }
    textView.attributedText = attributedString;
    if ([self.inputToolBarDelegate respondsToSelector:@selector(messageInputToolbarDidType:)]) {
        [self.inputToolBarDelegate messageInputToolbarDidType:self];
    }
    [self setNeedsLayout];
    [self configureRightAccessoryButtonState];
}

- (NSArray *)mediaAttachments
{
    NSAttributedString *attributedString = self.textInputView.attributedText;
    if (!_mediaAttachments || ![attributedString isEqualToAttributedString:self.attributedStringForMessageParts]) {
        self.attributedStringForMessageParts = attributedString;
        _mediaAttachments = [self mediaAttachmentsFromAttributedString:attributedString];
    }
    return _mediaAttachments;
}

- (void)setLeftAccessoryImage:(UIImage *)leftAccessoryImage
{
    _leftAccessoryImage = leftAccessoryImage;
    [self.leftAccessoryButton setImage:leftAccessoryImage  forState:UIControlStateNormal];
}

- (void)setRightAccessoryImage:(UIImage *)rightAccessoryImage
{
    _rightAccessoryImage = rightAccessoryImage;
    [self.rightAccessoryButton setImage:rightAccessoryImage forState:UIControlStateNormal];
}

- (void)setRightAccessoryButtonActiveColor:(UIColor *)rightAccessoryButtonActiveColor
{
    _rightAccessoryButtonActiveColor = rightAccessoryButtonActiveColor;
    [self.rightAccessoryButton setTitleColor:rightAccessoryButtonActiveColor forState:UIControlStateNormal];
}

- (void)setRightAccessoryButtonDisabledColor:(UIColor *)rightAccessoryButtonDisabledColor
{
    _rightAccessoryButtonDisabledColor = rightAccessoryButtonDisabledColor;
    [self.rightAccessoryButton setTitleColor:rightAccessoryButtonDisabledColor forState:UIControlStateDisabled];
}

- (void)setRightAccessoryButtonFont:(UIFont *)rightAccessoryButtonFont
{
    _rightAccessoryButtonFont = rightAccessoryButtonFont;
    [self.rightAccessoryButton.titleLabel setFont:rightAccessoryButtonFont];
}

#pragma mark - Actions

- (void)leftAccessoryButtonTapped
{
    [self.inputToolBarDelegate messageInputToolbar:self didTapLeftAccessoryButton:self.leftAccessoryButton];
}

- (void)rightAccessoryButtonTapped
{
    [self acceptAutoCorrectionSuggestion];
    if ([self.inputToolBarDelegate respondsToSelector:@selector(messageInputToolbarDidEndTyping:)]) {
        [self.inputToolBarDelegate messageInputToolbarDidEndTyping:self];
    }
    [self.inputToolBarDelegate messageInputToolbar:self didTapRightAccessoryButton:self.rightAccessoryButton];
    self.textInputView.text = @"";
    [self setNeedsLayout];
    self.mediaAttachments = nil;
    self.attributedStringForMessageParts = nil;
    [self configureRightAccessoryButtonState];
}

- (void)actionButtonTapped
{
    if ([self.inputToolBarDelegate respondsToSelector:@selector(messageInputToolbar:didTapActionButton:)]) {
        [self.inputToolBarDelegate messageInputToolbar:self didTapActionButton:self.actionButton];
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    if (self.rightAccessoryButton.imageView) {
        [self configureRightAccessoryButtonState];
    }

    if (textView.text.length > 0 && [self.inputToolBarDelegate respondsToSelector:@selector(messageInputToolbarDidType:)]) {
        [self.inputToolBarDelegate messageInputToolbarDidType:self];
    } else if (textView.text.length == 0 && [self.inputToolBarDelegate respondsToSelector:@selector(messageInputToolbarDidEndTyping:)]) {
        [self.inputToolBarDelegate messageInputToolbarDidEndTyping:self];
    }

    [self setNeedsLayout];
    
    self.textInputView.scrollEnabled = self.textInputView.frame.size.height > self.textViewMinScrollHeight;
    CGRect line = [textView caretRectForPosition:textView.selectedTextRange.start];
    if (!CGSizeEqualToSize(line.size, CGSizeZero)) {
        CGFloat overflow = line.origin.y + line.size.height - (textView.contentOffset.y + textView.bounds.size.height - textView.contentInset.bottom - textView.contentInset.top);
        if (overflow > 0) {
            // We are at the bottom of the visible text and introduced a line feed, scroll down. Scroll caret to visible area
            CGPoint offset = textView.contentOffset;
            offset.y += overflow;
            
            // Cannot animate with setContentOffset:animated: or caret will not appear
            [UIView animateWithDuration:.2 animations:^{
                [textView setContentOffset:offset];
            }];
        }
    }
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    // Workaround for automatic scrolling not occurring in some cases.
    [textView scrollRangeToVisible:textView.selectedRange];
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
    return YES;
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithTextAttachment:(NSTextAttachment *)textAttachment inRange:(NSRange)characterRange
{
    return YES;
}

#pragma mark - Helpers

- (NSArray *)mediaAttachmentsFromAttributedString:(NSAttributedString *)attributedString
{
    NSMutableArray *mediaAttachments = [NSMutableArray new];
    [attributedString enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, attributedString.length) options:0 usingBlock:^(id attachment, NSRange range, BOOL *stop) {
        if ([attachment isKindOfClass:[ATLMediaAttachment class]]) {
            ATLMediaAttachment *mediaAttachment = (ATLMediaAttachment *)attachment;
            [mediaAttachments addObject:mediaAttachment];
            return;
        }
        NSAttributedString *attributedSubstring = [attributedString attributedSubstringFromRange:range];
        NSString *substring = attributedSubstring.string;
        NSString *trimmedSubstring = [substring stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedSubstring.length == 0) {
            return;
        }
        ATLMediaAttachment *mediaAttachment = [ATLMediaAttachment mediaAttachmentWithText:trimmedSubstring];
        [mediaAttachments addObject:mediaAttachment];
    }];
    return mediaAttachments;
}

- (void)acceptAutoCorrectionSuggestion
{
    // This is a workaround to accept the current auto correction suggestion while not resigning as first responder. From: http://stackoverflow.com/a/27865136
    [self.textInputView.inputDelegate selectionWillChange:self.textInputView];
    [self.textInputView.inputDelegate selectionDidChange:self.textInputView];
}

#pragma mark - Send Button Enablement

- (void)configureRightAccessoryButtonState
{
    if (self.textInputView.text.length) {
        [self configureRightAccessoryButtonForText];
        self.rightAccessoryButton.enabled = YES;
    } else {
        if (self.displaysRightAccessoryImage) {
            [self configureRightAccessoryButtonForImage];
            self.rightAccessoryButton.enabled = YES;
        } else {
            [self configureRightAccessoryButtonForText];
            self.rightAccessoryButton.enabled = NO;
        }
    }
}

- (void)configureRightAccessoryButtonForText
{
    self.rightAccessoryButton.accessibilityLabel = ATLMessageInputToolbarSendButton;
    [self.rightAccessoryButton setImage:nil forState:UIControlStateNormal];
    self.rightAccessoryButton.contentEdgeInsets = UIEdgeInsetsMake(2, 0, 0, 0);
    self.rightAccessoryButton.titleLabel.font = self.rightAccessoryButtonFont;
    [self.rightAccessoryButton setTitle:ATLLocalizedString(@"atl.messagetoolbar.send.key", self.rightAccessoryButtonTitle, nil) forState:UIControlStateNormal];
    [self.rightAccessoryButton setTitleColor:self.rightAccessoryButtonActiveColor forState:UIControlStateNormal];
    [self.rightAccessoryButton setTitleColor:self.rightAccessoryButtonDisabledColor forState:UIControlStateDisabled];
    if (!self.displaysRightAccessoryImage && !self.textInputView.text.length) {
        self.rightAccessoryButton.enabled = NO;
    } else {
        self.rightAccessoryButton.enabled = YES;
    }
}

- (void)configureRightAccessoryButtonForImage
{
    self.rightAccessoryButton.enabled = YES;
    self.rightAccessoryButton.accessibilityLabel = ATLMessageInputToolbarLocationButton;
    self.rightAccessoryButton.contentEdgeInsets = UIEdgeInsetsZero;
    [self.rightAccessoryButton setTitle:nil forState:UIControlStateNormal];
    [self.rightAccessoryButton setImage:self.rightAccessoryImage forState:UIControlStateNormal];
}


@end
