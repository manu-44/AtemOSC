/* -LICENSE-START-
** Copyright (c) 2011 Blackmagic Design
**
** Permission is hereby granted, free of charge, to any person or organization
** obtaining a copy of the software and accompanying documentation covered by
** this license (the "Software") to use, reproduce, display, distribute,
** execute, and transmit the Software, and to prepare derivative works of the
** Software, and to permit third-parties to whom the Software is furnished to
** do so, all subject to the following:
** 
** The copyright notices in the Software and this entire statement, including
** the above license grant, this restriction and the following disclaimer,
** must be included in all copies of the Software, in whole or in part, and
** all derivative works of the Software, unless such copies or derivative
** works are solely in the form of machine-executable object code generated by
** a source language processor.
** 
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
** FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
** SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
** FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
** ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
** DEALINGS IN THE SOFTWARE.
** -LICENSE-END-
*/

#import "AppDelegate.h"
#include <libkern/OSAtomic.h>

@implementation AppDelegate

@synthesize window;
@synthesize isConnectedToATEM;
@synthesize mMixEffectBlock;
@synthesize mMixEffectBlockMonitor;
@synthesize keyers;
@synthesize dsk;
@synthesize switcherTransitionParameters;
@synthesize mMediaPool;
@synthesize mMediaPlayers;
@synthesize mStills;
@synthesize mMacroPool;
@synthesize mSuperSource;
@synthesize mMacroControl;
@synthesize mSuperSourceBoxes;
@synthesize mSwitcherInputAuxList;
@synthesize outPort;
@synthesize inPort;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSMenu* edit = [[[[NSApplication sharedApplication] mainMenu] itemWithTitle: @"Edit"] submenu];
    if ([[edit itemAtIndex: [edit numberOfItems] - 1] action] == NSSelectorFromString(@"orderFrontCharacterPalette:"))
        [edit removeItemAtIndex: [edit numberOfItems] - 1];
    if ([[edit itemAtIndex: [edit numberOfItems] - 1] action] == NSSelectorFromString(@"startDictation:"))
        [edit removeItemAtIndex: [edit numberOfItems] - 1];
    if ([[edit itemAtIndex: [edit numberOfItems] - 1] isSeparatorItem])
        [edit removeItemAtIndex: [edit numberOfItems] - 1];

	mSwitcherDiscovery = NULL;
	mSwitcher = NULL;
	mMixEffectBlock = NULL;
	mMediaPool = NULL;
    mMacroPool = NULL;
    isConnectedToATEM = NO;
    
    mOscReceiver = [[OSCReceiver alloc] initWithDelegate:self];
	
	mSwitcherMonitor = new SwitcherMonitor(self);
    mDownstreamKeyerMonitor = new DownstreamKeyerMonitor(self);
    mTransitionParametersMonitor = new TransitionParametersMonitor(self);
	mMixEffectBlockMonitor = new MixEffectBlockMonitor(self);
	
	mSwitcherDiscovery = CreateBMDSwitcherDiscoveryInstance();
	if (!mSwitcherDiscovery)
    {
		NSBeginAlertSheet(@"Could not create Switcher Discovery Instance.\nATEM Switcher Software may not be installed.\n",
							@"OK", nil, nil, window, self, @selector(sheetDidEndShouldTerminate:returnCode:contextInfo:), NULL, window, @"");
	}
    else
    {
        [self switcherDisconnected];		// start with switcher disconnected
    
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [mAddressTextField setStringValue:[prefs stringForKey:@"atem"]];
        NSLog(@"Value: %@", [prefs stringForKey:@"atem"]);
        
        [outgoing setIntValue:[prefs integerForKey:@"outgoing"]];
        [incoming setIntValue:[prefs integerForKey:@"incoming"]];
        [oscdevice setStringValue:[prefs objectForKey:@"oscdevice"]];
    
        //	make an osc manager- i'm using a custom in-port to record a bunch of extra conversion for the display, but you can just make a "normal" manager
        manager = [[OSCManager alloc] init];
    
        [self portChanged:self];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    NSTextField* textField = (NSTextField *)[aNotification object];
    bool validInput = true;
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    if (textField == oscdevice && ![[oscdevice stringValue] isEqualToString:@""])
    {
        if ([self isValidIPAddress:[oscdevice stringValue]])
            [prefs setObject:[oscdevice stringValue] forKey:@"oscdevice"];
        else
        {
            validInput = false;
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Invalid IP Adress"];
            [alert setInformativeText:@"Please enter a valid IP Address for 'OSC Out IP Adress'"];
            [alert beginSheetModalForWindow:window completionHandler:nil];
        }
    }
    
    else if (textField == mAddressTextField && ![[mAddressTextField stringValue] isEqualToString:@""])
    {
        if ([self isValidIPAddress:[mAddressTextField stringValue]])
            [prefs setObject:[mAddressTextField stringValue] forKey:@"atem"];
        else
        {
            validInput = false;
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Invalid IP Adress"];
            [alert setInformativeText:@"Please enter a valid IP Address for 'Switcher IP Adress'"];
            [alert beginSheetModalForWindow:window completionHandler:nil];
        }
    }
    
    [prefs setInteger:[outgoing intValue] forKey:@"outgoing"];
    [prefs setInteger:[incoming intValue] forKey:@"incoming"];
    [prefs synchronize];
    
    [self portChanged:self];
}

- (IBAction)portChanged:(id)sender
{
    [manager removeInput:inPort];
    [manager removeOutput:outPort];
    
    outPort = [manager createNewOutputToAddress:[oscdevice stringValue] atPort:[outgoing intValue] withLabel:@"atemOSC"];
    inPort = [manager createNewInputForPort:[incoming intValue] withLabel:@"atemOSC"];
    
    [manager setDelegate:mOscReceiver];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
	[self cleanUpConnection];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
	return YES;
}

- (void)sheetDidEndShouldTerminate:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[NSApp terminate:self];
}

- (IBAction)helpButtonPressed:(id)sender
{
    
    if ([sender tag] == 1)
    {
        //set helptext
        [heltTextView setAlignment:NSLeftTextAlignment];
        
        NSMutableAttributedString * helpString = [[NSMutableAttributedString alloc] initWithString:@""];
        NSDictionary *infoAttribute = @{NSFontAttributeName: [[NSFontManager sharedFontManager] fontWithFamily:@"Monaco" traits:NSUnboldFontMask|NSUnitalicFontMask weight:5 size:12]};
        NSDictionary *addressAttribute = @{NSFontAttributeName: [[NSFontManager sharedFontManager] fontWithFamily:@"Helvetica" traits:NSBoldFontMask weight:5 size:12]};
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"Transitions:\n" attributes:addressAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tT-Bar: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/bar\n" attributes:infoAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tCut: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/cut\n" attributes:infoAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tAuto-Cut: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/auto\n" attributes:infoAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tFade-to-black: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/ftb\n" attributes:infoAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nTransition type:\n" attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet to Mix: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/set-type/mix\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet to Dip: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/set-type/dip\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet to Wipe: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/set-type/wipe\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet to Stinger: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/set-type/sting\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet to DVE: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/set-type/dve\n" attributes:infoAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nUpstream Keyers:\n" attributes:addressAttribute]];
        for (int i = 0; i<keyers.size();i++)
        {
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tOn Air KEY %d toggle: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/usk/%d\n",i+1] attributes:infoAttribute]];
        }
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tBKGD: "] attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/nextusk/0\n"] attributes:infoAttribute]];
        for (int i = 0; i<keyers.size();i++)
        {
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tKEY %d: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/nextusk/%d\n",i+1] attributes:infoAttribute]];
        }
        
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nDownstream Keyers:\n" attributes:addressAttribute]];
        for (int i = 0; i<dsk.size();i++)
        {
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tAuto-Transistion DSK%d: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/dsk/%d\n",i+1] attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet DSK On Ait%d: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/dsk/on-air/%d\t<0|1>\n",i+1] attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tTie Next-Transistion DSK%d: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/dsk/tie/%d\n",i+1] attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Tie Next-Transistion DSK%d: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/dsk/set-tie/%d\t<0|1>\n",i+1] attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tToggle DSK%d: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/dsk/toggle/%d\n",i+1] attributes:infoAttribute]];
        }

        
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nSources:\n" attributes:addressAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nAux Outputs:\n" attributes:addressAttribute]];
        for (int i = 0; i<mSwitcherInputAuxList.size();i++)
        {
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Aux %d to Source: ",i+1] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/aux/%d\t<valid_program_source>\n",i+1] attributes:infoAttribute]];
        }
        
        if (mMediaPlayers.size() > 0)
        {
            uint32_t clipCount;
            uint32_t stillCount;
            HRESULT result;
            result = mMediaPool->GetClipCount(&clipCount);
            if (FAILED(result))
            {
                // the default number of clips
                clipCount = 2;
            }
            result = mMediaPool->GetStills(&mStills);
            if (FAILED(result))
            {
                // ATEM TVS only supports 20 stills, the others are 32
                stillCount = 20;
            }
            else
            {
                result = mStills->GetCount(&stillCount);
                if (FAILED(result))
                {
                    // ATEM TVS only supports 20 stills, the others are 32
                    stillCount = 20;
                }
            }
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nMedia Players:\n" attributes:addressAttribute]];
            for (int i = 0; i < mMediaPlayers.size(); i++)
            {
                for (int j = 0; j < clipCount; j++)
                {
                    [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet MP %d to Clip %d: ",i+1,j+1] attributes:  addressAttribute]];
                    [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/mplayer/%d/clip/%d\n",i+1,j+1] attributes:infoAttribute]];
                }
                for (int j = 0; j < stillCount; j++)
                {
                    [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet MP %d to Still %d: ",i+1,j+1] attributes:  addressAttribute]];
                    [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/mplayer/%d/still/%d\n",i+1,j+1] attributes:infoAttribute]];
                }
            }
        }
        
        
        if (mSuperSourceBoxes.size() > 0)
        {
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nSuper Source:\n" attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tValid values specified in <>\n\n" attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet the border enabled flag: " attributes:  addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/supersource/border-enabled\t<0|1>\n" attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet the border outer width: " attributes:  addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/supersource/border-outer\t<float>\n" attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet the border inner width: " attributes:  addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/supersource/border-inner\t<float>\n" attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet the border hue: " attributes:  addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/supersource/border-hue\t<float>\n" attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet the border saturation: " attributes:  addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/supersource/border-saturation\t<float>\n" attributes:infoAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tSet the border luminescence: " attributes:  addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/supersource/border-luminescence\t<float>\n" attributes:infoAttribute]];
            for (int i = 1; i <= mSuperSourceBoxes.size(); i++)
            {
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d enabled: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/enabled\t<0|1>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Input source: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/source\t<see sources for valid options>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Position X: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/x\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Position Y: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/y\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Size: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/size\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Cropped Enabled: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/cropped\t<0|1>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Crop Top: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/crop-top\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Crop Bottom: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/crop-bottom\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Crop Left: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/crop-left\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tSet Box %d Crop Right: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/crop-right\t<float>\n",i] attributes:infoAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tReset Box %d Crop: ",i] attributes:  addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/supersource/box/%d/crop-reset\t<1>\n",i] attributes:infoAttribute]];
            }
        }
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nMacros:\n" attributes:addressAttribute]];
        
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tGet the Maximum Number of Macros: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/macros/get-max-number\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tStop the currently active Macro (if any): " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/macros/stop\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tGet the Name of a Macro: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/macros/<index>/name\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tGet the Description of a Macro: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/macros/<index>/description\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tGet whether the Macro at <index> is valid: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/macros/<index>/is-valid\n" attributes:infoAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tRun the Macro at <index>: " attributes:addressAttribute]];
        [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/macros/<index>/run\n" attributes:infoAttribute]];
        
        [helpString addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0,helpString.length)];
        [[heltTextView textStorage] setAttributedString:helpString];
        
        helpPanel.isVisible = YES;
    }
    else if ([sender tag]==2)
    {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/danielbuechele/atemOSC/"]];
    }
}

- (IBAction)logButtonPressed:(id)sender
{
    [logTextView setTextColor:[NSColor whiteColor]];
    logPanel.isVisible = YES;
}

- (BOOL)isValidIPAddress:(NSString*) str
{
    const char *utf8 = [str UTF8String];
    int success;
    
    struct in_addr dst;
    success = inet_pton(AF_INET, utf8, &dst);
    if (success != 1) {
        struct in6_addr dst6;
        success = inet_pton(AF_INET6, utf8, &dst6);
    }
    
    return success == 1;
}

- (void)connectBMD
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* address = [mAddressTextField stringValue];
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
        dispatch_async(queue, ^{
        
            BMDSwitcherConnectToFailure            failReason;
            
            // Note that ConnectTo() can take several seconds to return, both for success or failure,
            // depending upon hostname resolution and network response times, so it may be best to
            // do this in a separate thread to prevent the main GUI thread blocking.
            HRESULT hr = mSwitcherDiscovery->ConnectTo((CFStringRef)address, &mSwitcher, &failReason);
            if (SUCCEEDED(hr))
            {
                [self switcherConnected];
            }
            else
            {
                NSString* reason;
                switch (failReason)
                {
                    case bmdSwitcherConnectToFailureNoResponse:
                        reason = @"No response from Switcher";
                        break;
                    case bmdSwitcherConnectToFailureIncompatibleFirmware:
                        reason = @"Switcher has incompatible firmware";
                        break;
                    case bmdSwitcherConnectToFailureCorruptData:
                        reason = @"Corrupt data was received during connection attempt";
                        break;
                    case bmdSwitcherConnectToFailureStateSync:
                        reason = @"State synchronisation failed during connection attempt";
                        break;
                    case bmdSwitcherConnectToFailureStateSyncTimedOut:
                        reason = @"State synchronisation timed out during connection attempt";
                        break;
                    default:
                        reason = @"Connection failed for unknown reason";
                }
                //Delay 2 seconds before everytime connect/reconnect
                //Because the session ID from ATEM switcher will alive not more then 2 seconds
                //After 2 second of idle, the session will be reset then reconnect won't cause error
                double delayInSeconds = 2.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                               ^(void){
                                   //To run in background thread
                                   [self switcherDisconnected];
                               });
                [self logMessage:[NSString stringWithFormat:@"%@", reason]];
            }
        });
    });
}

- (void)switcherConnected
{
	HRESULT result;
	IBMDSwitcherMixEffectBlockIterator* iterator = NULL;
	IBMDSwitcherMediaPlayerIterator* mediaPlayerIterator = NULL;
	IBMDSwitcherSuperSourceBoxIterator* superSourceIterator = NULL;
    isConnectedToATEM = YES;
    
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
    {
        self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:0x00FFFFFF reason:@"receiving OSC messages"];
    }
    
    OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/led/green"];
    [newMsg addFloat:1.0];
    [outPort sendThisMessage:newMsg];
    newMsg = [OSCMessage createWithAddress:@"/atem/led/red"];
    [newMsg addFloat:0.0];
    [outPort sendThisMessage:newMsg];
	
	//[mConnectButton setEnabled:NO];			// disable Connect button while connected
    dispatch_async(dispatch_get_main_queue(), ^{
        [greenLight setHidden:NO];
        [redLight setHidden:YES];
    });
	
	NSString* productName;
	if (FAILED(mSwitcher->GetProductName((CFStringRef*)&productName)))
	{
		[self logMessage:@"Could not get switcher product name"];
		return;
	}
	
    dispatch_async(dispatch_get_main_queue(), ^{
        [mSwitcherNameLabel setStringValue:productName];
        [productName release];
    });
    
	mSwitcher->AddCallback(mSwitcherMonitor);
    
	// Get the mix effect block iterator
	result = mSwitcher->CreateIterator(IID_IBMDSwitcherMixEffectBlockIterator, (void**)&iterator);
	if (FAILED(result))
	{
		[self logMessage:@"Could not create IBMDSwitcherMixEffectBlockIterator iterator"];
		return;
	}
	
	// Use the first Mix Effect Block
	if (S_OK != iterator->Next(&mMixEffectBlock))
	{
		[self logMessage:@"Could not get the first IBMDSwitcherMixEffectBlock"];
		return;
	}
    
    
    //Upstream Keyer
    IBMDSwitcherKeyIterator* keyIterator = NULL;
    result = mMixEffectBlock->CreateIterator(IID_IBMDSwitcherKeyIterator, (void**)&keyIterator);
    IBMDSwitcherKey* key = NULL;
    if (SUCCEEDED(result))
    {
        while (S_OK == keyIterator->Next(&key))
        {
            keyers.push_back(key);
        }
    }
    keyIterator->Release();
    keyIterator = NULL;
    
    //Downstream Keyer
    IBMDSwitcherDownstreamKeyIterator* dskIterator = NULL;
    result = mSwitcher->CreateIterator(IID_IBMDSwitcherDownstreamKeyIterator, (void**)&dskIterator);
    IBMDSwitcherDownstreamKey* downstreamKey = NULL;
    if (SUCCEEDED(result))
    {
        while (S_OK == dskIterator->Next(&downstreamKey))
        {
            dsk.push_back(downstreamKey);
            downstreamKey->AddCallback(mDownstreamKeyerMonitor);
        }
    }
    dskIterator->Release();
    dskIterator = NULL;


    // Media Players
    result = mSwitcher->CreateIterator(IID_IBMDSwitcherMediaPlayerIterator, (void**)&mediaPlayerIterator);
    if (FAILED(result))
    {
        [self logMessage:@"Could not create IBMDSwitcherMediaPlayerIterator iterator"];
        return;
    }
    
	IBMDSwitcherMediaPlayer* mediaPlayer = NULL;
    while (S_OK == mediaPlayerIterator->Next(&mediaPlayer))
    {
        mMediaPlayers.push_back(mediaPlayer);
    }
    mediaPlayerIterator->Release();
    mediaPlayerIterator = NULL;
    
    // get media pool
    result = mSwitcher->QueryInterface(IID_IBMDSwitcherMediaPool, (void**)&mMediaPool);
    if (FAILED(result))
    {
        [self logMessage:@"Could not get IBMDSwitcherMediaPool interface"];
        return;
    }
    
    // get macro pool
    result = mSwitcher->QueryInterface(IID_IBMDSwitcherMacroPool, (void**)&mMacroPool);
    if (FAILED(result))
    {
        [self logMessage:@"Could not get IID_IBMDSwitcherMacroPool interface"];
        return;
    }
    
    // get macro controller
    result = mSwitcher->QueryInterface(IID_IBMDSwitcherMacroControl, (void**)&mMacroControl);
    if (FAILED(result))
    {
        [self logMessage:@"Could not get IID_IBMDSwitcherMacroControl interface"];
        return;
    }
    
	// Super source
    if (mSuperSource) {
        result = mSuperSource->CreateIterator(IID_IBMDSwitcherSuperSourceBoxIterator, (void**)&superSourceIterator);
        if (FAILED(result))
        {
            [self logMessage:@"Could not create IBMDSwitcherSuperSourceBoxIterator iterator"];
            return;
        }
        IBMDSwitcherSuperSourceBox* superSourceBox = NULL;
        while (S_OK == superSourceIterator->Next(&superSourceBox))
        {
            mSuperSourceBoxes.push_back(superSourceBox);
        }
        superSourceIterator->Release();
        superSourceIterator = NULL;
    }
    
    switcherTransitionParameters = NULL;
    mMixEffectBlock->QueryInterface(IID_IBMDSwitcherTransitionParameters, (void**)&switcherTransitionParameters);
    switcherTransitionParameters->AddCallback(mTransitionParametersMonitor);
    
    
	mMixEffectBlock->AddCallback(mMixEffectBlockMonitor);
	
    self->mMixEffectBlockMonitor->updateSliderPosition();
	
finish:
	if (iterator)
		iterator->Release();
}

- (void)switcherDisconnected
{

    isConnectedToATEM = NO;
	if (self.activity)
        [[NSProcessInfo processInfo] endActivity:self.activity];
    
    self.activity = nil;
    
    OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/led/green"];
    [newMsg addFloat:0.0];
    [outPort sendThisMessage:newMsg];
    newMsg = [OSCMessage createWithAddress:@"/atem/led/red"];
    [newMsg addFloat:1.0];
    [outPort sendThisMessage:newMsg];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [mSwitcherNameLabel setStringValue:@""];
        [greenLight setHidden:YES];
        [redLight setHidden:NO];
    });
	
    [self cleanUpConnection];

    [self connectBMD];
}

- (void)cleanUpConnection
{
    while (mSwitcherInputAuxList.size())
    {
        mSwitcherInputAuxList.back()->Release();
        mSwitcherInputAuxList.pop_back();
    }
    
    while (mMediaPlayers.size())
    {
        mMediaPlayers.back()->Release();
        mMediaPlayers.pop_back();
    }
    
    if (mStills)
    {
        mStills->Release();
        mStills = NULL;
    }
    
    if (mMediaPool)
    {
        mMediaPool->Release();
        mMediaPool = NULL;
    }
    
    while (mSuperSourceBoxes.size())
    {
        mSuperSourceBoxes.back()->Release();
        mSuperSourceBoxes.pop_back();
    }
    
    while (keyers.size())
    {
        keyers.back()->Release();
        keyers.pop_back();
    }
    
    while (dsk.size())
    {
        dsk.back()->Release();
        dsk.back()->RemoveCallback(mDownstreamKeyerMonitor);
        dsk.pop_back();
    }
    
    if (mMixEffectBlock)
    {
        mMixEffectBlock->RemoveCallback(mMixEffectBlockMonitor);
        mMixEffectBlock->Release();
        mMixEffectBlock = NULL;
    }
    
    // disconnect monitors
    if (mSwitcher)
    {
        mSwitcher->RemoveCallback(mSwitcherMonitor);
        mSwitcher->Release();
        mSwitcher = NULL;
    }
    
    if (switcherTransitionParameters)
    {
        switcherTransitionParameters->RemoveCallback(mTransitionParametersMonitor);
    }
}

- (void)logMessage:(NSString *)message
{
    if (message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendMessage:message];
        });
        NSLog(@"%@", message);
    }
}

- (void)appendMessage:(NSString *)message
{
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = nil;
    formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    NSString *messageWithNewLine = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:now], message];
    [formatter release];
    
    // Append string to textview
    [logTextView.textStorage appendAttributedString:[[NSAttributedString alloc]initWithString:messageWithNewLine]];
    
    [logTextView scrollRangeToVisible: NSMakeRange(logTextView.string.length, 0)];
    
    [logTextView setTextColor:[NSColor whiteColor]];
}

@end
