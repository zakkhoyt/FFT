//
//  ViewController.m
//  FFT
//
//  Created by Zakk Hoyt on 8/27/14.
//  Copyright (c) 2014 Zakk Hoyt. All rights reserved.
//

#import "ViewController.h"
#import <CoreAudio/CoreAudioTypes.h>

#import <Accelerate/Accelerate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>


typedef struct {
    unsigned int size;
    float *samples;
} SampleInfo;


@interface ViewController ()

@end

@implementation ViewController
            
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(SampleInfo)printFloatDataFromAudioFile:(NSString*)name{

    NSString * source = [[NSBundle mainBundle] pathForResource:name ofType:@"wav"]; // SPECIFY YOUR FILE FORMAT
    
    const char *cString = [source cStringUsingEncoding:NSASCIIStringEncoding];
    
    CFStringRef str = CFStringCreateWithCString(
                                                NULL,
                                                cString,
                                                kCFStringEncodingMacRoman
                                                );
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(
                                                          kCFAllocatorDefault,
                                                          str,
                                                          kCFURLPOSIXPathStyle,
                                                          false
                                                          );
    
    ExtAudioFileRef fileRef;
    ExtAudioFileOpenURL(inputFileURL, &fileRef);
    
    
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = 44100;   // GIVE YOUR SAMPLING RATE
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat;
    audioFormat.mBitsPerChannel = sizeof(Float32) * 8;
    audioFormat.mChannelsPerFrame = 1; // Mono
    audioFormat.mBytesPerFrame = audioFormat.mChannelsPerFrame * sizeof(Float32);  // == sizeof(Float32)
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBytesPerPacket = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame; // = sizeof(Float32)
    
    // 3) Apply audio format to the Extended Audio File
    ExtAudioFileSetProperty(
                            fileRef,
                            kExtAudioFileProperty_ClientDataFormat,
                            sizeof (AudioStreamBasicDescription), //= audioFormat
                            &audioFormat);
    
    int numSamples = 1024; //How many samples to read in at a time
    UInt32 sizePerPacket = audioFormat.mBytesPerPacket; // = sizeof(Float32) = 32bytes
    UInt32 packetsPerBuffer = numSamples;
    UInt32 outputBufferSize = packetsPerBuffer * sizePerPacket;
    
    // So the lvalue of outputBuffer is the memory location where we have reserved space
    UInt8 *outputBuffer = (UInt8 *)malloc(sizeof(UInt8 *) * outputBufferSize);

    
    
    AudioBufferList convertedData ;//= malloc(sizeof(convertedData));
    
    convertedData.mNumberBuffers = 1;    // Set this to 1 for mono
    convertedData.mBuffers[0].mNumberChannels = audioFormat.mChannelsPerFrame;  //also = 1
    convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
    convertedData.mBuffers[0].mData = outputBuffer; //

    UInt32 frameCount = numSamples;
    float *samplesAsCArray;
    int j =0;
//    double floatDataArray[133120]   ; // SPECIFY YOUR DATA LIMIT MINE WAS 882000 , SHOULD BE EQUAL TO OR MORE THAN DATA LIMIT
    float *floatDataArray = malloc(sizeof(float)* 882000); //133120);

    while (frameCount > 0) {
        ExtAudioFileRead(
                         fileRef,
                         &frameCount,
                         &convertedData
                         );
        if (frameCount > 0)  {
            AudioBuffer audioBuffer = convertedData.mBuffers[0];
            samplesAsCArray = (float *)audioBuffer.mData; // CAST YOUR mData INTO FLOAT
            
            for (int i =0; i<1024 /*numSamples */; i++) { //YOU CAN PUT numSamples INTEAD OF 1024
                
                floatDataArray[j] = (double)samplesAsCArray[i] ; //PUT YOUR DATA INTO FLOAT ARRAY
//                printf("\n%f",floatDataArray[j]);  //PRINT YOUR ARRAY'S DATA IN FLOAT FORM RANGING -1 TO +1
                j++;
            }
        }
    }
    
    SampleInfo sampleInfo;
    sampleInfo.samples = floatDataArray;
    sampleInfo.size = j;
    return sampleInfo;
}

-(void)performFFT{
    // Code taken from: http://batmobile.blogs.ilrt.org/fourier-transforms-on-an-iphone/
    
//    SampleInfo sampleInfo = [self printFloatDataFromAudioFile:@"sin_110"];
//    SampleInfo sampleInfo = [self printFloatDataFromAudioFile:@"sin_220"];
//    SampleInfo sampleInfo = [self printFloatDataFromAudioFile:@"sin_440"];
    SampleInfo sampleInfo = [self printFloatDataFromAudioFile:@"sweep"];
//    SampleInfo sampleInfo = [self printFloatDataFromAudioFile:@"white"];
    float *samples = sampleInfo.samples;
    int numSamples = 2048;//1024;

    
    // Setup the length
    vDSP_Length log2n = log2f(numSamples);
    
    // Calculate the weights array. This is a one-off operation.
    FFTSetup fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
    
    // For an FFT, numSamples must be a power of 2, i.e. is always even
    int nOver2 = numSamples/2;
    
    // Populate *window with the values for a hamming window function
    float *window = (float *)malloc(sizeof(float) * numSamples);
    vDSP_hamm_window(window, numSamples, 0);
    // Window the samples
    vDSP_vmul(samples, 1, window, 1, samples, 1, numSamples);
    
    // Define complex buffer
    COMPLEX_SPLIT A;
    A.realp = (float *) malloc(nOver2*sizeof(float));
    A.imagp = (float *) malloc(nOver2*sizeof(float));
    
    // Pack samples:
    // C(re) -> A[n], C(im) -> A[n+1]
    vDSP_ctoz((COMPLEX*)samples, 2, &A, 1, numSamples/2);
    
    //Perform a forward FFT using fftSetup and A
    //Results are returned in A
    vDSP_fft_zrip(fftSetup, &A, 1, log2n, FFT_FORWARD);
    
    //Convert COMPLEX_SPLIT A result to magnitudes
    float *amp = malloc(sizeof(float) * numSamples);
    amp[0] = A.realp[0]/(numSamples*2);
    float max = 0;
    int indexOfMax = -1;
    for(int i=1; i<numSamples; i++) {
        amp[i]=A.realp[i]*A.realp[i]+A.imagp[i]*A.imagp[i];
        printf("i[%ld]: %.1f %ldHz \n", (long)i, amp[i], (long)22000 * i/numSamples);
        
        if(amp[i] > max) {
            max = amp[i];
            indexOfMax = i;
        }
    }
    printf("max value of %f at index %ld which is %f way though", max, (long)indexOfMax, (float)(indexOfMax / (float)numSamples));

}

- (IBAction)buttonTouchUpInside:(id)sender {
    [self performFFT];
}

@end
