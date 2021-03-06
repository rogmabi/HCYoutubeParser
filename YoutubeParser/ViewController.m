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
#import "TMCache.h"
#import "LBYouTubeExtractor.h"

#import "AFNetworking.h"
#import <AFNetworking/UIKit+AFNetworking.h>

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

@interface ViewController () <UIActionSheetDelegate, UITableViewDataSource, UITableViewDelegate, UIDocumentInteractionControllerDelegate, LBYouTubeExtractorDelegate> {
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

@property (nonatomic, strong) AFURLSessionManager *manager;

@end

@implementation ViewController {
    NSURL *_urlToLoad;
    NSMutableData *receivedData;
    long long expectedBytes;
}

@synthesize progress, dic;

#pragma mark
#pragma mark View Load / Appear

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [_playButton setImage:[UIImage imageNamed:@"play_button"] forState:UIControlStateNormal];
    [_submitButton addTarget:self action:@selector(submitYouTubeURL:) forControlEvents:UIControlEventTouchUpInside];
    [_playButton addTarget:self action:@selector(playVideo:) forControlEvents:UIControlEventTouchUpInside];
    
    if (!_urlToLoad) {
        _playButton.hidden = YES;
    }
    
    self.progress.hidden = YES;
    
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    
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
    // reset the pasteboard
    [[UIPasteboard generalPasteboard] setValue:@"" forPasteboardType:UIPasteboardNameGeneral];
    
    if (!_urlToLoad) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:_urlToLoad];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd 'at' HH:mm"];
    NSString *videoDirectory = [documentsDirectory stringByAppendingPathComponent:@"Downloaded Videos"];
    NSString *path = [videoDirectory stringByAppendingPathComponent:[[df stringFromDate:[NSDate date]] stringByAppendingString:@".mp4"]];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    
    NSProgress *progressObj;
    NSURLSessionDownloadTask *downloadTask = [self.manager downloadTaskWithRequest:request progress:&progressObj destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        NSURL *documentsDirectoryPath = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
        return [documentsDirectoryPath URLByAppendingPathComponent:[response suggestedFilename]];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        
        if (!error) {
            
            [[NSFileManager defaultManager] moveItemAtURL:filePath toURL:[NSURL fileURLWithPath:path] error:&error];
            
            if (error) {
                NSLog(@"Could not move file at path %@ to path %@", filePath, path);
                NSLog(@"Error: %@", error.localizedDescription);
            }
            else {
                // on top
                [self.downloadedVideoPaths insertObject:path.lastPathComponent atIndex:0];
                [self.tableView reloadData];
                
                _urlToLoad = [NSURL fileURLWithPath:path];
                NSLog(@"File downloaded to: %@", filePath);
            }
            
            progress.hidden = YES;
            
            
        }
        else {
            NSLog(@"Error: %@", error.localizedDescription);
        }
    }];
    
    progress.progress = 0.0f;
    progress.hidden = NO;
    
    [progress setProgressWithDownloadProgressOfTask:downloadTask animated:YES];
    [downloadTask resume];
}


#pragma mark
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
    [_playButton setHidden:YES];
    
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
                self.posterIV.image = image;
            });
        }
        else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
            [alert show];
        }
        
        [self videoURLForYoutubeURL:url];
    }];
}

- (void)videoURLForYoutubeURL:(NSURL *)url {
    [HCYoutubeParser h264videosWithYoutubeURL:url completeBlock:^(NSDictionary *videoDictionary, NSError *error) {
        
        if (!error && videoDictionary) {
            currentVideoDictionary = videoDictionary;
            [self askQualityForVideo];
        }
        else {
            NSLog(@"Error with Youtube API: %@\n\nGoing to extract the URL instead...", [error localizedDescription]);
            [self extractVideoURL];
        }
        
    }];
}

- (void)askQualityForVideo {
    if (!currentVideoDictionary) {
        NSLog(@"Nothing to show");
        self.posterIV.hidden = YES;
        self.playButton.hidden = YES;
        self.activityIndicator.hidden = YES;
        return;
    }
    
    _activityIndicator.hidden = YES;
    
    NSLog(@"Video Dictionary is\n\n%@", currentVideoDictionary);
    
    UIActionSheet *as = [[UIActionSheet alloc] initWithTitle:@"Chose the quality to download" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"High (1080p or 720p)", @"Medium", @"Small", nil];
    as.tag = kASTagQuality;
    [as showInView:self.view];
}

- (void)extractVideoURL {
    NSURL *url = [NSURL URLWithString:_urlTextField.text];
    LBYouTubeExtractor* extractor = [[LBYouTubeExtractor alloc] initWithURL:url quality:LBYouTubeVideoQualityLarge];
    extractor.delegate = self;
    [extractor startExtracting];
}

- (void)playVideo:(NSDictionary *)videoDictionary quality:(NSString *)quality {
    
    NSDictionary *qualities = videoDictionary;
    NSString *URLString = nil;
    
    if ([qualities objectForKey:quality] != nil) {
        URLString = [qualities objectForKey:quality];
        _urlToLoad = [NSURL URLWithString:URLString];
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
    Float64 durationSeconds = CMTimeGetSeconds([asset duration]);
    CMTime thumbnailTime;
    if (durationSeconds >= 2) {
        thumbnailTime = CMTimeMakeWithSeconds(2, 600);
    }
    else {
        thumbnailTime = kCMTimeZero;
    }
    CGImageRef imageRef = [imageGenerator copyCGImageAtTime:thumbnailTime actualTime:NULL error:NULL];
    UIImage *thumbnail = [UIImage imageWithCGImage:imageRef];
    thumbnail = [thumbnail imageByScalingAndCroppingForSize:CGSizeMake(88, 88)];
    CGImageRelease(imageRef);  // CGImageRef won't be released by ARC
    return thumbnail;
}

#pragma mark
#pragma mark LBYouTubeExtractorDelegate

-(void)youTubeExtractor:(LBYouTubeExtractor *)extractor didSuccessfullyExtractYouTubeURL:(NSURL *)videoURL {
    if (videoURL) _urlToLoad = [videoURL copy];
    [self cleanURL];
    NSLog(@"extracted videoURL is %@", _urlToLoad);
    [_playButton setHidden:NO];
    _activityIndicator.hidden = YES;
    [_playButton setImage:[UIImage imageNamed:@"play_button"] forState:UIControlStateNormal];
    
    [self startDownload];
}

- (void)cleanURL {
    NSString *url = _urlToLoad.absoluteString;
    url = [url stringByReplacingOccurrencesOfString:@"%3A" withString:@":"];
    url = [url stringByReplacingOccurrencesOfString:@"%2F" withString:@"//"];
    _urlToLoad = [NSURL URLWithString:url];
}

-(void)youTubeExtractor:(LBYouTubeExtractor *)extractor failedExtractingYouTubeURLWithError:(NSError *)error {
    _urlToLoad = nil;
    [_playButton setHidden:YES];
    _activityIndicator.hidden = YES;
    
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Couldn't find a working URL.\nBetter chance next time!" delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
    [av show];
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
            else if ([currentVideoDictionary objectForKey:@"hd720"]) {
                [self playVideo:currentVideoDictionary quality:@"hd720"];
            }
            else {
                [self playVideo:currentVideoDictionary quality:@"high"];
            }
        }
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+1) {
            [self playVideo:currentVideoDictionary quality:@"medium"];
        }
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+2) {
            [self playVideo:currentVideoDictionary quality:@"small"];
        }
        
        if (buttonIndex != actionSheet.cancelButtonIndex) {
            if (currentVideoDictionary && _urlToLoad) {
                [self startDownload];
            }
            _playButton.hidden = NO;
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
    
    UIImage *cachedThumb;
    
    if ( (cachedThumb = [[TMCache sharedCache] objectForKey:videoPath]) ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.imageView.image = cachedThumb;
        });
    }
    else {
        // create, set and cache
        [UIImage videoThumbFromVideoPath:videoPath completion:^(UIImage *thumb) {
            if (thumb) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    cell.imageView.image = thumb;
                });
                [[TMCache sharedCache] setObject:thumb forKey:videoPath];
            }
        }];
    }
    
    [cell setAccessoryType:UITableViewCellAccessoryDetailButton];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *path = [self videoPathForVideoName:[self.downloadedVideoPaths objectAtIndex:indexPath.row]];
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (error) {
        NSLog(@"Could not remove item at path %@.\n\nError is %@", path, [error localizedDescription]);
    }
    else {
        if (indexPath.row <= self.downloadedVideoPaths.count) {
            [self.downloadedVideoPaths removeObjectAtIndex:indexPath.row];
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        else {
            NSLog(@"index out of bound! %d out of %d", indexPath.row, self.downloadedVideoPaths.count);
        }
    }
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
