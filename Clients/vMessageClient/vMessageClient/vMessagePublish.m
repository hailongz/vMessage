//
//  vMessagePublish.m
//  vMessageClient
//
//  Created by zhang hailong on 13-6-27.
//  Copyright (c) 2013年 hailong.org. All rights reserved.
//

#import "vMessagePublish.h"

#define INPUT_DATA_SIZE  10240

@interface vMessagePublish(){
    CFHTTPMessageRef _request;
    CFHTTPMessageRef _response;
    BOOL _executing;
    BOOL _finished;
    
    struct {
        int state;
        NSUInteger index;
        NSUInteger length;
    } _outputState;
    
    struct {
        NSUInteger index;
        NSUInteger length;
        int state;
        const char * protocol;
        const char * version;
        const char * statusCode;
        const char * status;
        const char * key;
        const char * value;
    } _inputState;
    uint8_t _inputData[INPUT_DATA_SIZE];
}

@property(retain) NSInputStream * inputStream;
@property(retain) NSOutputStream * outputStream;
@property(retain) NSRunLoop * runloop;
@property(retain) NSData * outputData;

@end

@implementation vMessagePublish

@synthesize delegate =_delegate;
@synthesize client = _client;
@synthesize to = _to;
@synthesize inputStream = _inputStream;
@synthesize outputStream = _outputStream;
@synthesize runloop = _runloop;
@synthesize outputData = _outputData;

-(void) dealloc{
    
    [_outputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
    [_outputStream setDelegate:nil];
    [_outputStream close];
    
    [_inputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
    [_inputStream setDelegate:nil];
    [_inputStream close];

    [_inputStream release];
    [_outputStream release];
    
    if(_request){
        CFRelease(_request);
    }
    if(_response){
        CFRelease(_response);
    }
    [_client release];
    [_to release];
    [_outputData release];
    [_runloop release];
    [super dealloc];
}

-(id) initWithClient:(vMessageClient *) client to:(NSString *) to{
    
    if(client == nil || [to length] ==0){
        [self autorelease];
        return nil;
    }
    
    if((self = [super init])){
        _client = [client retain];
        _to = [to retain];
    }
    return self;
}

-(BOOL) willRequest:(CFHTTPMessageRef) request{
    return NO;
}

-(BOOL) hasSendData{
    return NO;
}

-(void) didHasSpaceStream:(NSOutputStream *) stream{
    
}

-(void) didFinishResponse:(CFHTTPMessageRef) response{
    if([_delegate respondsToSelector:@selector(vMessagePublish:didFinishResponse:)]){
        [_delegate vMessagePublish:self didFinishResponse:response];
    }
    _finished = YES;
}

-(void) onDidFailError:(NSError *) error{
    if([_delegate respondsToSelector:@selector(vMessagePublish:didFailError:)]){
        [_delegate vMessagePublish:self didFailError:error];
    }
    _finished = YES;
}

-(BOOL) isConcurrent{
    return YES;
}

-(BOOL) isReady{
    
    if(_request == nil){
        
        _request = CFHTTPMessageCreateRequest(nil, (CFStringRef)@"POST", (CFURLRef)[NSURL URLWithString:_to relativeToURL:_client.url], (CFStringRef) @"1.1");
        
        CFHTTPMessageAddAuthentication(_request, NULL, (CFStringRef) _client.user, (CFStringRef) _client.password, kCFHTTPAuthenticationSchemeBasic, NO);
        
    }
    
    return [self willRequest:_request];
}

-(BOOL) isExecuting{
    return _executing;
}

-(BOOL) isFinished {
    return _finished;
}

-(void) main{
    
    _executing = YES;
    
    @autoreleasepool {
        self.runloop = [NSRunLoop currentRunLoop];
        
        NSURL * url = _client.url;
        NSString * host = [url host];
        NSUInteger port = [[url port] unsignedIntValue];
        
        if(port == 0){
            port = 80;
        }
        
        CFStreamCreatePairWithSocketToHost(nil, (CFStringRef) host, port
                                           , (CFReadStreamRef *) & _inputStream, (CFWriteStreamRef *)& _outputStream);
        
        
        [_inputStream setDelegate:self];
        [_inputStream scheduleInRunLoop:_runloop forMode:NSRunLoopCommonModes];
        [_outputStream setDelegate:self];
        [_outputStream scheduleInRunLoop:_runloop forMode:NSRunLoopCommonModes];
        
        [_outputStream open];
        [_inputStream open];
        
        while(![self isCancelled] && ! _finished){
            @autoreleasepool {
                [_runloop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
            }
        }

    }
    
    _executing = NO;
}

-(void) stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode{
    
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
        {
            
        }
            break;
        case NSStreamEventHasBytesAvailable:
        {
            if(_inputStream == aStream){
                
                while([_inputStream hasBytesAvailable]){
                    
                    if(_inputState.length == 0){
                        if(_inputState.index < sizeof(_inputData)){
                            NSInteger len = [_inputStream read:_inputData + _inputState.index
                                                     maxLength:sizeof(_inputData) - _inputState.index];
                            if(len <= 0){
                                return;
                            }
                            _inputState.length = len;
                        }
                        else{
                            NSInteger len = [_inputStream read:_inputData maxLength:sizeof(_inputData)];
                            if(len <= 0){
                                return;
                            }
                            _inputState.length = len;
                            _inputState.index = 0;
                        }
                    }
                    
                    uint8_t * pByte = _inputData + _inputState.index;
                    
                    while(_inputState.length){
                        
                        switch (_inputState.state) {
                            case 0:
                            {
                                // HTTP
                                if(*pByte == '/'){
                                    *pByte = 0;
                                    _inputState.state =1;
                                    _inputState.version = 0;
                                }
                                else if(_inputState.protocol == 0){
                                    _inputState.protocol = (char *) pByte;
                                }
                            }
                                break;
                            case 1:
                            {
                                // HTTP/1.1
                                if(*pByte == ' '){
                                    *pByte = 0;
                                    _inputState.statusCode = (char *) pByte + 1;
                                    _inputState.state = 2;
                                }
                                else if(_inputState.version ==0){
                                    _inputState.version = (char *) pByte;
                                }
                            }
                                break;
                            case 2:
                            {
                                // HTTP/1.1 200
                                if(*pByte == ' '){
                                    *pByte = 0;
                                    _inputState.state = 3;
                                    _inputState.status = 0;
                                }
                                else if(_inputState.statusCode == 0){
                                    _inputState.statusCode = (char *) pByte;
                                }
                            }
                                break;
                            case 3 :
                            {
                                // HTTP/1.1 200 OK
                                if( * pByte == '\r'){
                                    * pByte = 0;
                                }
                                else if( * pByte == '\n'){
                                    _inputState.state = 4;
                                    _inputState.key = 0;
                                    
                                    
                                    CFStringRef version = CFStringCreateWithCString(nil, _inputState.version, kCFStringEncodingUTF8);
                                    
                                    if(_response){
                                        CFRelease(_response);
                                        _response = nil;
                                    }
                                    
                                    _response = CFHTTPMessageCreateResponse(nil, atoi(_inputState.statusCode), nil, version);
                        
                                    CFRelease(version);
                                    
                                }
                                else if(_inputState.status ==0){
                                    _inputState.status = (char *) pByte;
                                }
                                
                            }
                                break;
                            case 4:
                            {
                                // key
                                if(*pByte == ':'){
                                    *pByte = 0;
                                    
                                    _inputState.state = 5;
                                    _inputState.value = 0;
                                }
                                else if(*pByte == '\r'){
                                    
                                }
                                else if(*pByte == '\n'){
                                    
                                    _inputState.state = 6;
                                    _inputState.key = 0;
                                    _inputState.value = 0;
                                    
                                    [_inputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
                                    [_outputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
                                    [_inputStream setDelegate:nil];
                                    [_outputStream setDelegate:nil];
                                    [_inputStream close];
                                    [_outputStream close];
                                    
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        if(!_finished){
                                            [self didFinishResponse:_response];
                                        }
                                    });
                                    
                                    return;
                                }
                                else if(_inputState.key == 0){
                                    _inputState.key = (char *) pByte;
                                }
                            }
                                break;
                            case 5:
                            {
                                // value
                                if(*pByte == '\r'){
                                    
                                    *pByte = 0;
                                }
                                else if(*pByte == '\n'){
                                    *pByte = 0;
                                    
                                    if(_inputState.key && _inputState.value){
                                        NSString * key = [NSString stringWithCString:_inputState.key encoding:NSUTF8StringEncoding];
                                        NSString * value = [NSString stringWithCString:_inputState.value encoding:NSUTF8StringEncoding];
                                        
                                        CFHTTPMessageSetHeaderFieldValue(_response, (CFStringRef) key, (CFStringRef) value);
                                    }
                                    
                                    _inputState.key = 0;
                                    _inputState.value = 0;
                                    _inputState.state = 4;
                                }
                                else if(_inputState.value == 0){
                                    if(*pByte == ' '){
                                        
                                    }
                                    else{
                                        _inputState.value = (char *) pByte;
                                    }
                                }
                            }
                                break;
                            
                            default:
                                break;
                        }
                        
                        _inputState.index ++;
                        _inputState.length --;
                        pByte ++;
                    }
                }
            }
        }
            break;
        case NSStreamEventHasSpaceAvailable:
        {
            if(_outputStream == aStream){
                while ([_outputStream hasSpaceAvailable]) {
                    
                    if(_outputState.state == 0){
                    
                        CFDataRef data = CFHTTPMessageCopySerializedMessage(_request);
                        
                        NSInteger len = [_outputStream write:CFDataGetBytePtr(data) maxLength:CFDataGetLength(data)];
                        
                        //write(STDOUT_FILENO, CFDataGetBytePtr(data), CFDataGetLength(data));
                        
                        if(len <=0){
                            [_inputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
                            [_outputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
                            [_inputStream setDelegate:nil];
                            [_outputStream setDelegate:nil];
                            [_inputStream close];
                            [_outputStream close];
                            
                            NSError * error = aStream.streamError;
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if(! _finished){
                                    [self onDidFailError:error];
                                }
                            });
                        }
                        
                        if(len < CFDataGetLength(data)){
                            self.outputData = (id) data;
                            _outputState.index = len;
                            _outputState.length = CFDataGetLength(data) - len;
                        }
                        else{
                            _outputState.state = 1;
                        }
                        
                        CFRelease(data);
                    }
                    else if(_outputState.state == 1){
                        
                        if(![self hasSendData]){
                            [_outputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
                            [_outputStream setDelegate:nil];
                            [_outputStream close];
                            break;
                        }
                        
                        [self didHasSpaceStream:_outputStream];
                    }
                    else {
                        break;
                    }
                    
                }
            }
        }
            break;
        case NSStreamEventEndEncountered:
        {
            
        }
            break;
        case NSStreamEventErrorOccurred:
        {
            [_inputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
            [_outputStream removeFromRunLoop:_runloop forMode:NSRunLoopCommonModes];
            [_inputStream setDelegate:nil];
            [_outputStream setDelegate:nil];
            [_inputStream close];
            [_outputStream close];
            
            NSError * error = aStream.streamError;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if(! _finished){
                    [self onDidFailError:error];
                }
            });
        }
            break;
        default:
            break;
    }
    
}

@end
