//
//  ViewController.m
//  YoutubeParser
//
//  Created by Simon Andersson on 9/22/12.
//  Copyright (c) 2012 Hiddencode.me. All rights reserved.
//

#import "ViewController.h"
#import "HCYoutubeParser.h"
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import "UIImage+YSImage.h"

typedef void(^DrawRectBlock)(CGRect rect);

typedef NS_ENUM(NSUInteger, kLocalTags) {
    kASTagQuality = 1,
    kASTagAction
};

@interface HCView : UIView {
@private
    DrawRectBlock block;
}

- (void)setDrawRectBlock:(DrawRectBlock)b;

@end

@interface UIView (DrawRect)

+ (UIView *)viewWithFrame:(CGRect)frame drawRect:(DrawRectBlock)block;
@end

@implementation HCView

- (void)setDrawRectBlock:(DrawRectBlock)b {
    block = [b copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (block)
        block(rect);
}

@end

@implementation UIView (DrawRect)

+ (UIView *)viewWithFrame:(CGRect)frame drawRect:(DrawRectBlock)block {
    HCView *view = [[HCView alloc] initWithFrame:frame];
    [view setDrawRectBlock:block];
    return view;
}

@end

@interface ViewController () <UIActionSheetDelegate, UITableViewDataSource, UITableViewDelegate, UIDocumentInteractionControllerDelegate> {
    NSDictionary *currentVideoDictionary;
}

@property (weak, nonatomic) IBOutlet UIButton *submitButton;
@property (weak, nonatomic) IBOutlet UITextField *urlTextField;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIProgressView *progress;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIImageView *posterIV;

@property (nonatomic, strong) NSMutableArray *downloadedVideoPaths;

@property (nonatomic, strong) UIDocumentInteractionController *dic;

@end

@implementation ViewController {
    NSURL *_urlToLoad;
    NSMutableData *receivedData;
    long long expectedBytes;
    BOOL justLoaded;
}

@synthesize progress, dic;

#pragma mark
#pragma mark View Load / Appear

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [_submitButton addTarget:self action:@selector(submitYouTubeURL:) forControlEvents:UIControlEventTouchUpInside];
    [_playButton addTarget:self action:@selector(showActionSheet:) forControlEvents:UIControlEventTouchUpInside];
    
    self.progress.hidden = YES;
    
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    
    justLoaded = YES;
    
    [self registerNotifications];
}

- (void)registerNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(listDownloadedVideos) name:@"UIApplicationDidBecomeActiveNotification" object:nil];
}

- (void)unregisterNotifications {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"UIApplicationDidBecomeActiveNotification" object:nil];
}

#pragma mark
#pragma mark Methods

- (void)checkLinkInPasteboard {
    if ([UIPasteboard generalPasteboard].URL || [UIPasteboard generalPasteboard].string) {
        NSString *link;
        if ([UIPasteboard generalPasteboard].URL) {
            link = [UIPasteboard generalPasteboard].URL.absoluteString;
        }
        else {
            link = [UIPasteboard generalPasteboard].string;
        }
        if (link) {
            _urlTextField.text = link;
            [self submitYouTubeURL:nil];
        }
    }
}

- (void)listDownloadedVideos {
    
    [self checkLinkInPasteboard];
    
    self.downloadedVideoPaths = [NSMutableArray array];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *videoDirectory = [documentsDirectory stringByAppendingPathComponent:@"Downloaded Videos"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoDirectory]) {
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtPath:videoDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Error: %@", [error localizedDescription]);
        }
        return;
    }
    
    NSError *error;
    NSArray *dirContents;
    dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:videoDirectory error:&error];
    
    if (dirContents) {
        for (NSString *path in dirContents) {
            [self.downloadedVideoPaths insertObject:path atIndex:0];
        }
    }
    
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)showActionSheet:(id)sender {
    UIActionSheet *as = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Play", @"Download", nil];
    as.tag = kASTagAction;
    [as showInView:self.view];
}

- (void)playVideo:(id)sender {
    if (_urlToLoad) {
        MPMoviePlayerViewController *mp = [[MPMoviePlayerViewController alloc] initWithContentURL:_urlToLoad];
        [self presentViewController:mp animated:YES completion:nil];
    }
}

- (void)downloadVideo:(id)sender {
    if (_urlToLoad) {
        [self startDownload];
    }
}

#pragma mark
#pragma mark Downloading
-(void)startDownload {
    NSURL *url = _urlToLoad;
    NSURLRequest *theRequest = [NSURLRequest requestWithURL:url
                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                            timeoutInterval:60];
    receivedData = [[NSMutableData alloc] initWithLength:0];
    NSURLConnection * connection = [[NSURLConnection alloc] initWithRequest:theRequest
                                                                   delegate:self
                                                           startImmediately:YES];
    NSLog(@"Connection started immediately: %@", connection);
}


- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    progress.hidden = NO;
    [receivedData setLength:0];
    expectedBytes = [response expectedContentLength];
}

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [receivedData appendData:data];
    float progressive = (float)[receivedData length] / (float)expectedBytes;
    [progress setProgress:progressive];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    progress.hidden = YES;
}

- (NSCachedURLResponse *) connection:(NSURLConnection *)connection willCacheResponse:    (NSCachedURLResponse *)cachedResponse {
    return nil;
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd 'at' HH:mm"];
    NSString *videoDirectory = [documentsDirectory stringByAppendingPathComponent:@"Downloaded Videos"];
    NSString *path = [videoDirectory stringByAppendingPathComponent:[[df stringFromDate:[NSDate date]] stringByAppendingString:@".mp4"]];
    NSLog(@"Writing to path %@", path);
    NSLog(@"Succeeded! Received %d bytes of data",[receivedData length]);
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    BOOL written = [receivedData writeToFile:path atomically:YES];
    if (!written) {
        NSLog(@"Couldn't write data to path %@", path);
    }
    progress.hidden = YES;
    
    // on top
    [self.downloadedVideoPaths insertObject:path atIndex:0];
    [self.tableView reloadData];
}

#pragma mark Youtube

- (NSString *)videoDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *videoDirectory = [documentsDirectory stringByAppendingPathComponent:@"Downloaded Videos"];
    return videoDirectory;
}

- (NSString *)videoPathForVideoName:(NSString *)videoName {
    NSString *videoDirectory = [self videoDirectory];
    NSString *videoPath = [videoDirectory stringByAppendingPathComponent:videoName];
    return videoPath;
}

- (void)submitYouTubeURL:(id)sender {
    
    if ([_urlTextField canResignFirstResponder]) {
        [_urlTextField resignFirstResponder];
    }
    _urlToLoad = nil;
    [_playButton setImage:nil forState:UIControlStateNormal];
    
    NSURL *url = [NSURL URLWithString:_urlTextField.text];
    
    if (!url ) {
        UIAlertView *as = [[UIAlertView alloc] initWithTitle:@"Not A URL" message:@"Please paste a valid URL" delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
        [as show];
        return;
    }
    
    
    _activityIndicator.hidden = NO;
    [HCYoutubeParser thumbnailForYoutubeURL:url thumbnailSize:YouTubeThumbnailDefaultHighQuality completeBlock:^(UIImage *image, NSError *error) {
        
        if (!error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.posterIV setImage:image];
                [self.posterIV setContentMode:UIViewContentModeScaleAspectFit];
            });
            
            [HCYoutubeParser h264videosWithYoutubeURL:url completeBlock:^(NSDictionary *videoDictionary, NSError *error) {
                
                _playButton.hidden = NO;
                _activityIndicator.hidden = YES;
                
                currentVideoDictionary = videoDictionary;
                
                NSLog(@"Video Dictionary is\n\n%@", videoDictionary);
                
                UIActionSheet *as = [[UIActionSheet alloc] initWithTitle:@"Chose the quality" delegate:self cancelButtonTitle:@"Ok" destructiveButtonTitle:nil otherButtonTitles:@"High (1080p)", @"High (720p)", @"Medium", @"Small", nil];
                as.tag = kASTagQuality;
                [as showInView:self.view];
                
            }];
        }
        else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
            [alert show];
        }
    }];
}

- (void)playVideo:(NSDictionary *)videoDictionary quality:(NSString *)quality {
    
    NSDictionary *qualities = videoDictionary;
    NSString *URLString = nil;
    
    if ([qualities objectForKey:quality] != nil) {
        URLString = [qualities objectForKey:quality];
        _urlToLoad = [NSURL URLWithString:URLString];
        
        [_playButton setImage:[UIImage imageNamed:@"play_button"] forState:UIControlStateNormal];
        
    }
    else {
        [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Couldn't find youtube video" delegate:nil cancelButtonTitle:@"Close" otherButtonTitles: nil] show];
    }
}

- (UIImage *)videoThumbFromVideoPath:(NSString *)videoPath {
    NSString *fullVideoPath = videoPath;
    NSURL *sourceURL = [NSURL fileURLWithPath:fullVideoPath];
    AVAsset *asset = [AVAsset assetWithURL:sourceURL];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc]initWithAsset:asset];
    CMTime thumbnailTime = CMTimeMake(1, 1);
    CGImageRef imageRef = [imageGenerator copyCGImageAtTime:thumbnailTime actualTime:NULL error:NULL];
    UIImage *thumbnail = [UIImage imageWithCGImage:imageRef];
    thumbnail = [thumbnail imageByScalingAndCroppingForSize:CGSizeMake(88, 88)];
    CGImageRelease(imageRef);  // CGImageRef won't be released by ARC
    return thumbnail;
}

#pragma mark
#pragma mark UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    if (actionSheet.tag == kASTagQuality) {
        if (buttonIndex == actionSheet.firstOtherButtonIndex) {
            // high
            if ([currentVideoDictionary objectForKey:@"hd1080"]) {
                [self playVideo:currentVideoDictionary quality:@"hd1080"];
            }
            else {
                [self playVideo:currentVideoDictionary quality:@"hd720"];
            }
        }
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+1) {
            [self playVideo:currentVideoDictionary quality:@"hd720"];
        }
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+2) {
            [self playVideo:currentVideoDictionary quality:@"medium"];
        }
        else {
            [self playVideo:currentVideoDictionary quality:@"small"];
        }
    }
    else if(actionSheet.tag == kASTagAction) {
        if (buttonIndex == actionSheet.firstOtherButtonIndex) {
            // Watch
            [self playVideo:nil];
        }
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+1) {
            // Download
            [self downloadVideo:nil];
        }
    }
}

#pragma mark 
#pragma mark UIDocumentInteractionControllerDelegate
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

#pragma mark
#pragma mark UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.downloadedVideoPaths ? self.downloadedVideoPaths.count : 0;
}

// Row display. Implementers should *always* try to reuse cells by setting each cell's reuseIdentifier and querying for available reusable cells with dequeueReusableCellWithIdentifier:
// Cell gets various attributes set automatically based on table (separators) and data source (accessory views, editing controls)

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *ReuseIdentifier = @"MyIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ReuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ReuseIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    NSString *videoName = [self.downloadedVideoPaths objectAtIndex:indexPath.row];
    cell.textLabel.text = videoName.lastPathComponent;
    cell.detailTextLabel.text = @"Tap to Open In...";
    NSString *videoPath = [self videoPathForVideoName:videoName];
    cell.imageView.image = [UIImage imageNamed:@"placeholder"];
    
    [UIImage videoThumbFromVideoPath:videoPath completion:^(UIImage *thumb) {
        if (thumb) {
//            dispatch_async(dispatch_get_main_queue(), ^{
                cell.imageView.image = thumb;
                [cell setNeedsDisplay];
//            });
        }
    }];
    
    [cell setAccessoryType:UITableViewCellAccessoryDetailButton];
    
    return cell;
}

#pragma mark UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *videoName = [self.downloadedVideoPaths objectAtIndex:indexPath.row];
    NSString *videoPath = [self videoPathForVideoName:videoName];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSURL *fileUrl = [NSURL fileURLWithPath:videoPath];
    if (fileUrl) {
        dic = [UIDocumentInteractionController interactionControllerWithURL:fileUrl];
        dic.delegate = self;
        [dic presentOpenInMenuFromRect:cell.frame inView:tableView animated:YES];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    NSString *videoName = [self.downloadedVideoPaths objectAtIndex:indexPath.row];
    NSString *videoPath = [self videoPathForVideoName:videoName];
    _urlToLoad = [NSURL fileURLWithPath:videoPath];
    [self playVideo:nil];
}

#pragma mark - Memory Management

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidUnload {
    [self setSubmitButton:nil];
    [self setUrlTextField:nil];
    [self setActivityIndicator:nil];
    [self setPlayButton:nil];
    
    [super viewDidUnload];
}

#pragma mark
#pragma mark Auto Rotation
- (BOOL)shouldAutorotate {
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
        return YES;
    }
    else {
        return NO;
    }
}

- (NSUInteger)supportedInterfaceOrientations {
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
        return UIInterfaceOrientationMaskAll;
    }
    else {
        return UIInterfaceOrientationMaskPortrait;
    }
}

#pragma mark - UITextFieldDelegate Implementation

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([textField canResignFirstResponder]) {
        [textField resignFirstResponder];
    }
    return YES;
}

- (void)dealloc {
    [self unregisterNotifications];
}

@end
