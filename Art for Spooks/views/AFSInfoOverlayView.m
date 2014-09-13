//
//  AFSInfoOverlayView.m
//  Art for Spooks
//
//  Created by Nicholas A Knouf on 9/6/14.
//  Copyright (c) 2014 zeitkunst. All rights reserved.
//

#import <Accounts/Accounts.h>
#import <Social/Social.h>
#import <ImageIO/ImageIO.h>
#import <CoreLocation/CoreLocation.h>

#import "FlickrKit.h"
#import "AFSDroneCoords.h"
#import "AFSMarkovChain.h"
#import "AFSInfoOverlayView.h"

@interface AFSInfoOverlayView ()
@property (nonatomic, strong) ACAccountStore *accountStore;
@property (nonatomic, strong) AFSDroneCoords *droneCoords;
@property (nonatomic, strong) AFSMarkovChain *markovChain;
@property (nonatomic, retain) FKDUNetworkOperation *checkAuthOp;
@property (nonatomic, retain) FKImageUploadNetworkOperation *uploadOp;
@property (nonatomic, retain) NSString *userName;
@property (nonatomic, retain) NSString *userID;
@property (nonatomic, retain) NSString *albumName;
@property (strong, nonatomic) ALAssetsLibrary *assetsLibrary;
@end

@implementation AFSInfoOverlayView

// More info: http://stackoverflow.com/questions/11708597/loadnibnamed-vs-initwithframe-dilemma-for-setting-frames-height-and-width
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self = [[[NSBundle mainBundle] loadNibNamed:@"AFSInfoOverlayView" owner:nil options:nil] objectAtIndex:0];
        [self setFrame:frame];
        self.infoOverlayWebViewHidden = YES;
        [self.infoWebView setHidden:self.infoOverlayWebViewHidden];
        
        // Setup drone coords and markov chain
        self.droneCoords = [[AFSDroneCoords alloc] initWithFilename:@"drone_coords"];
        self.markovChain = [[AFSMarkovChain alloc] init];
        [self.markovChain loadModelWithMaxChars:70];
        
        // Hide status label
        [self.overlayStatusLabel setHidden:YES];
        [self.overlayStatusLabel setBackgroundColor:[UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:0.25]];
        //CGRect overlayStatusLabelFrame = self.overlayStatusLabel.frame;
        //[self.overlayStatusLabel setFrame:CGRectMake(overlayStatusLabelFrame.origin.x, overlayStatusLabelFrame.origin.y, overlayStatusLabelFrame.size.width, overlayStatusLabelFrame.size.height + 900)];
        
        // Hide overlay web view
        [self.infoWebView setHidden:YES];
        
        // Get our assets library
        self.assetsLibrary = [[ALAssetsLibrary alloc] init];
        
        // Create our group
        self.albumName = @"Art for Spooks";
        NSString *albumNameBlock = self.albumName;
        [self.assetsLibrary addAssetsGroupAlbumWithName:self.albumName
                                            resultBlock:^(ALAssetsGroup *group) {
                                                NSLog(@"Added album:%@", albumNameBlock);
                                            }
                                           failureBlock:^(NSError *error) {
                                               NSLog(@"error adding album");
                                           }];
        
        // Subscribe to notifications for loss of tracking
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(noTargetsCallback:) name:@"NoTargetsNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(targetsCallback:) name:@"TargetsNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(captureFaceCallback:) name:@"CaptureFaceNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preAugmentFaceCallback:) name:@"PreAugmentFaceNotification" object:nil];
        
        // Check if there is a stored token
        // You should do this once on app launch
        self.checkAuthOp = [[FlickrKit sharedFlickrKit] checkAuthorizationOnCompletion:^(NSString *userName, NSString *userId, NSString *fullName, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!error) {
                    self.userName = userName;
                    self.userID = userId;
                    //NSLog(@"userID: %@", self.userID);
                } else {
                    self.userID = nil;
                }
            });
        }];
        
    }
    //[self.infoWebView setHidden:YES];
    return self;
}

- (void)setOverlayInfoWebView:(NSString *)infoHTMLFilename {
    //  Load html from a local file for the about screen
    NSString *aboutFilePath = [[NSBundle mainBundle] pathForResource:infoHTMLFilename
                                                              ofType:@"html"];
    
    NSString* htmlString = [NSString stringWithContentsOfFile:aboutFilePath
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    
    NSString *aPath = [[NSBundle mainBundle] bundlePath];
    NSURL *anURL = [NSURL fileURLWithPath:aPath];
    [self.infoWebView loadHTMLString:htmlString baseURL:anURL];
}

- (IBAction)overlayQuestionMarkTapped:(id)sender {
    self.infoOverlayWebViewHidden = !self.infoOverlayWebViewHidden;
    [self.infoWebView setHidden:self.infoOverlayWebViewHidden];
}

// From: https://stackoverflow.com/questions/7965299/write-uiimage-along-with-metadata-exif-gps-tiff-in-iphones-photo-library
- (NSDictionary *) gpsDictionaryForLocation:(CLLocation *)location
{
    CLLocationDegrees exifLatitude  = location.coordinate.latitude;
    CLLocationDegrees exifLongitude = location.coordinate.longitude;
    
    NSString * latRef;
    NSString * longRef;
    if (exifLatitude < 0.0) {
        exifLatitude = exifLatitude * -1.0f;
        latRef = @"S";
    } else {
        latRef = @"N";
    }
    
    if (exifLongitude < 0.0) {
        exifLongitude = exifLongitude * -1.0f;
        longRef = @"W";
    } else {
        longRef = @"E";
    }
    
    NSMutableDictionary *locDict = [[NSMutableDictionary alloc] init];
    
    [locDict setObject:location.timestamp forKey:(NSString*)kCGImagePropertyGPSTimeStamp];
    [locDict setObject:latRef forKey:(NSString*)kCGImagePropertyGPSLatitudeRef];
    [locDict setObject:[NSNumber numberWithFloat:exifLatitude] forKey:(NSString *)kCGImagePropertyGPSLatitude];
    [locDict setObject:longRef forKey:(NSString*)kCGImagePropertyGPSLongitudeRef];
    [locDict setObject:[NSNumber numberWithFloat:exifLongitude] forKey:(NSString *)kCGImagePropertyGPSLongitude];
    [locDict setObject:[NSNumber numberWithFloat:location.horizontalAccuracy] forKey:(NSString*)kCGImagePropertyGPSDOP];
    [locDict setObject:[NSNumber numberWithFloat:location.altitude] forKey:(NSString*)kCGImagePropertyGPSAltitude];
    
    return locDict;
    
}

- (NSDictionary *) iptcDictionary
{
    NSMutableDictionary *iptcDict = [[NSMutableDictionary alloc] init];
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Deleuze1992" ofType:@"txt"];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    
    int contentLength = (int)[content length];
    NSLog(@"Content length: %d", contentLength);

    int lowerBound = 0;
    int upperBound = (contentLength - 2001);
    int offset = lowerBound + arc4random() % (upperBound - lowerBound);
    NSLog(@"Offset: %d", offset);
    NSString *contentCut = [content substringWithRange:NSMakeRange(offset, 2000)];
    
    // TODO: Add done casulties to metadata
    [iptcDict setObject:contentCut forKey:(NSString *)kCGImagePropertyIPTCCaptionAbstract];
    [iptcDict setObject:@"Art for Spooks" forKey:(NSString *)kCGImagePropertyIPTCCredit];
    [iptcDict setObject:@"Art for Spooks" forKey:(NSString *)kCGImagePropertyIPTCSource];
    [iptcDict setObject:@"NSA, spooks, surveillance, Zelda" forKey:(NSString *)kCGImagePropertyIPTCKeywords];
    
    return iptcDict;
}

- (IBAction)overlayShareTapped:(id)sender {
    //NSMutableString *generatedText = [self.markovChain generateTextWith:50 limitToMaxChars:NO];
    //NSLog(@"Generated text: %@", generatedText);
    
    // Get the screenshot
    UIImage *screenshot = [self takeScreenshot];
    
    // Get some coords
    NSArray *chosenCoord = [self.droneCoords randomDroneCoord];
    NSMutableString *status = [self.markovChain generateTextWith:50 limitToMaxChars:YES];
    NSMutableString *description = [self.markovChain generateTextWith:150 limitToMaxChars:NO];
    
    // Set the metadata
    CLLocation *location = [[CLLocation alloc] initWithLatitude:[chosenCoord[0] doubleValue] longitude:[chosenCoord[1] doubleValue]];
    NSMutableDictionary *imageMetadata = [[NSMutableDictionary alloc] init];
    [imageMetadata setObject:[self gpsDictionaryForLocation:location] forKey:(NSString*)kCGImagePropertyGPSDictionary];
    [imageMetadata setObject:[self iptcDictionary] forKey:(NSString *)kCGImagePropertyIPTCDictionary];
    
    // Get the assets group
    __block ALAssetsGroup* groupToAddTo;
    NSString *albumNameBlock = self.albumName;
    [self.assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAlbum
                                usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                                    if ([[group valueForProperty:ALAssetsGroupPropertyName] isEqualToString:albumNameBlock]) {
                                        NSLog(@"found album %@", albumNameBlock);
                                        groupToAddTo = group;
                                    }
                                }
                              failureBlock:^(NSError* error) {
                                  NSLog(@"failed to enumerate albums:\nError: %@", [error localizedDescription]);
                              }];
    
    // Same image to assets library
    CGImageRef img = [screenshot CGImage];
    [self.assetsLibrary writeImageToSavedPhotosAlbum:img
                                      metadata:imageMetadata
                               completionBlock:^(NSURL* assetURL, NSError* error) {
                                   if (error.code == 0) {
                                       NSLog(@"saved image completed:\nurl: %@", assetURL);
                                       
                                       // try to get the asset
                                       [self.assetsLibrary assetForURL:assetURL
                                                     resultBlock:^(ALAsset *asset) {
                                                         // assign the photo to the album
                                                         [groupToAddTo addAsset:asset];
                                                         NSLog(@"Added %@ to %@", [[asset defaultRepresentation] filename], @"Art for Spooks");
                                                         
                                                     }
                                                    failureBlock:^(NSError* error) {
                                                        NSLog(@"failed to retrieve image asset:\nError: %@ ", [error localizedDescription]);
                                                    }];
                                       // Finally, after it's been added, upload everything
                                       [self uploadScreenshot:screenshot withAssetURL:assetURL andStatus:status andDescription:description andCoords:chosenCoord];
                                   }
                                   else {
                                       NSLog(@"saved image failed.\nerror code %i\n%@", error.code, [error localizedDescription]);
                                   }
                               }];
    

    
    
    
}

- (void) uploadScreenshot:(UIImage *)screenshot withAssetURL:(NSURL *)assetURL andStatus:(NSMutableString *)status andDescription:(NSMutableString *)description andCoords:(NSArray *)chosenCoord {
    NSDictionary *uploadArgs = @{@"title": status, @"description": description, @"is_public": @"1", @"is_friend": @"0", @"is_family": @"0", @"hidden": @"1"};
    
    //self.progressView.progress = 0.0;
    NSLog(@"newAssetURL: %@", assetURL);
	self.uploadOp =  [[FlickrKit sharedFlickrKit] uploadAssetURL:assetURL args:uploadArgs completion:^(NSString *imageID, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (error) {
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
				[alert show];
                [self.overlayStatusLabel setText:error.localizedDescription];
                if (statusLabelTimer == nil) {
                    [self createStatusLabelTimer];
                }
			} else {
				//NSString *msg = [NSString stringWithFormat:@"Uploaded image ID %@", imageID];
				//UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Done" message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
				//[alert show];
                [status appendFormat:@": http://www.flickr.com/photos/%@/%@/", self.userID, imageID];
                [self tweetWithStatus:status andCoords:chosenCoord andImage:screenshot];
			}
            [self.uploadOp removeObserver:self forKeyPath:@"uploadProgress" context:NULL];
        });
	}];
    [self.uploadOp addObserver:self forKeyPath:@"uploadProgress" options:NSKeyValueObservingOptionNew context:NULL];
    [self.overlayStatusLabel setHidden:NO];
    [self.overlayStatusLabel setText:@"Uploading screenshot to Flickr and posting to Twitter, Facebook, and Tumblr..."];

}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([keyPath isEqualToString:@"uploadProgress"]) {
            CGFloat progress = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
            if (progress >= 1.0f) {
                //[self.overlayStatusLabel setText:@"Screenshot uploaded to Flickr"];
            }
        }
        //CGFloat progress = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
        //self.progressView.progress = progress;
        //[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    });
}

- (void)tweetWithStatus:(NSString *)status andCoords:(NSArray *) chosenCoord andImage:(UIImage *) image {
    self.accountStore = [[ACAccountStore alloc] init];
    //NSArray *chosenCoord = [self.droneCoords randomDroneCoord];
    NSLog(@"lat: %@; long: %@", chosenCoord[0], chosenCoord[1]);
    
    NSLog(@"Status length is: %d", [status length]);
    ACAccountType *twitterType =
    [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    SLRequestHandler requestHandler =
    ^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
        if (responseData) {
            NSInteger statusCode = urlResponse.statusCode;
            NSDictionary *postResponseData =
            [NSJSONSerialization JSONObjectWithData:responseData
                                            options:NSJSONReadingMutableContainers
                                              error:NULL];
            if (statusCode >= 200 && statusCode < 300) {
                
                NSLog(@"[SUCCESS!] Created Tweet with ID: %@; postResponseData: %@", postResponseData[@"id_str"], postResponseData);
                //NSLog(@"[SUCCESS!] Created Tweet with ID: %@", postResponseData[@"id_str"]);
                if (statusLabelTimer == nil) {
                    [self performSelectorOnMainThread:@selector(createStatusLabelTimer) withObject:nil waitUntilDone:YES];
                }
            }
            else {
                [self.overlayStatusLabel setText:@"Problem posting to Twitter"];
                [self createStatusLabelTimer];
                NSLog(@"[ERROR] Server responded: status code %d %@, responseData %@", statusCode,
                      [NSHTTPURLResponse localizedStringForStatusCode:statusCode], postResponseData);
            }
        }
        else {
            NSLog(@"[ERROR] An error occurred while posting: %@", [error localizedDescription]);
        }
    };
    
    ACAccountStoreRequestAccessCompletionHandler accountStoreHandler =
    ^(BOOL granted, NSError *error) {
        if (granted) {
            NSArray *accounts = [self.accountStore accountsWithAccountType:twitterType];
            NSURL *url = [NSURL URLWithString:@"https://api.twitter.com"
                          @"/1.1/statuses/update_with_media.json"];
            NSDictionary *params = @{
                                     @"status" : status,
                                     @"lat": chosenCoord[0],
                                     @"long": chosenCoord[1]};
            SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter
                                                    requestMethod:SLRequestMethodPOST
                                                              URL:url
                                                       parameters:params];
            NSData *imageData = UIImageJPEGRepresentation(image, 1.f);
            [request addMultipartData:imageData
                             withName:@"media[]"
                                 type:@"image/jpeg"
                             filename:[status substringWithRange:NSMakeRange(0, 10)]];
            [request setAccount:[accounts lastObject]];
            [request performRequestWithHandler:requestHandler];
        }
        else {
            NSLog(@"[ERROR] An error occurred while asking for user authorization: %@",
                  [error localizedDescription]);
        }
    };
    
    [self.accountStore requestAccessToAccountsWithType:twitterType
                                               options:NULL
                                            completion:accountStoreHandler];
    //self.tweetLabel.text = @"Tweeting...";
    
}

- (UIImage *)takeScreenshot
{
    CGSize imageSize = CGSizeZero;
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsPortrait(orientation)) {
        imageSize = [UIScreen mainScreen].bounds.size;
    } else {
        imageSize = CGSizeMake([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width);
    }
    
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, window.center.x, window.center.y);
        CGContextConcatCTM(context, window.transform);
        CGContextTranslateCTM(context, -window.bounds.size.width * window.layer.anchorPoint.x, -window.bounds.size.height * window.layer.anchorPoint.y);
        if (orientation == UIInterfaceOrientationLandscapeLeft) {
            CGContextRotateCTM(context, M_PI_2);
            CGContextTranslateCTM(context, 0, -imageSize.width);
        } else if (orientation == UIInterfaceOrientationLandscapeRight) {
            CGContextRotateCTM(context, -M_PI_2);
            CGContextTranslateCTM(context, -imageSize.height, 0);
        } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
            CGContextRotateCTM(context, M_PI);
            CGContextTranslateCTM(context, -imageSize.width, -imageSize.height);
        }
        if ([window respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        } else {
            [window.layer renderInContext:context];
        }
        CGContextRestoreGState(context);
    }
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Notifications
- (void) noTargetsCallback:(NSNotification *)notification {
    [self.overlayShareButton setHidden:YES];
}

- (void) targetsCallback:(NSNotification *)notification {
    [self.overlayShareButton setHidden:NO];
}

- (void) captureFaceCallback:(NSNotification *)notification {
    [self.overlayStatusLabel setHidden:NO];
    self.overlayStatusLabel.textColor = [UIColor redColor];
    [self.overlayStatusLabel setBackgroundColor:[UIColor blackColor]];
    [self.overlayStatusLabel setText:@"Capturing face...hold tablet in front of your face at arm's length for best results"];
}

- (void) preAugmentFaceCallback:(NSNotification *)notification {
    [self.overlayStatusLabel setText:@""];
    self.overlayStatusLabel.textColor = [UIColor blackColor];
    [self.overlayStatusLabel setBackgroundColor:[UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:0.25]];
    [self.overlayStatusLabel setHidden:YES];
}

#pragma mark - Tracking timer methods

// Create the status label timer
- (void)createStatusLabelTimer
{
    [self.overlayStatusLabel setText:@"Successfully posted to Flickr, Twitter, Facebook, and Tumblr"];
    statusLabelTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(statusLabelTimerFired:) userInfo:nil repeats:NO];
}

// Terminate the tracking lost timer
- (void)terminateStatusLabelTimer
{
    [statusLabelTimer invalidate];
    statusLabelTimer = nil;
}


// Tracking lost timer fired, pause video playback
- (void)statusLabelTimerFired:(NSTimer*)timer
{
    [self.overlayStatusLabel setHidden:YES];
    statusLabelTimer = nil;
}


/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
