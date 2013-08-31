//
//  vMessageResourcePublish.m
//  vMessageClient
//
//  Created by Zhang Hailong on 13-6-29.
//  Copyright (c) 2013年 hailong.org. All rights reserved.
//

#import "vMessageResourcePublish.h"

#define SBUF_SIZE   4096
#define SBUF_ITEM_SIZE   5000

@interface vMessageResourcePublish(){

    struct {
        uint8_t data[SBUF_SIZE];
        int index;
        int length;
    } sbuf;
    
    int _fno;
    
}

@end

@implementation vMessageResourcePublish

@synthesize filePath = _filePath;
@synthesize fileEOF = _fileEOF;
@synthesize contentType = _contentType;

-(void) dealloc{
    if(_fno >0){
        close(_fno);
    }
    [_filePath release];
    [_contentType release];
    [super dealloc];
}

-(id) initWithClient:(vMessageClient *) client to:(NSString *) to filePath:(NSString *) filePath{
    
    if((self = [super initWithClient:client to:to])){
        
        _fileEOF = YES;
        
        _filePath = [filePath retain];
        
        _fno = open([filePath UTF8String], O_RDONLY);
        
        if(_fno == -1){
            [self autorelease];
            return nil;
        }
    }
    
    return self;
}

-(BOOL) willRequest:(CFHTTPMessageRef)request{
    
    CFHTTPMessageSetHeaderFieldValue(request, (CFStringRef) @"Content-Type"
                                     , (CFStringRef) _contentType);
    
    CFHTTPMessageSetHeaderFieldValue(request, (CFStringRef) @"Transfer-Encoding"
                                     , (CFStringRef) @"chunked");
    
    
    return YES;
}

-(BOOL) didHasSpaceStream:(NSOutputStream *) stream{
    
    char buf[SBUF_ITEM_SIZE];
    int len,llen;
    
    while ([stream hasSpaceAvailable]) {
        
        while(sbuf.length == 0){
            
            sbuf.length = read(_fno, sbuf.data, sizeof(sbuf.data));
            sbuf.index = 0;
            
            if(sbuf.length == 0){
                
                if(_fileEOF){
                    
                    len = sprintf(buf,"0\r\n\r\n");
                    
                    if( len != [stream write: (uint8_t *) buf maxLength:len]){
                        
                        [self didFailError:[stream streamError]];
                        
                        return NO;
                    }
                    
                    return NO;
                }
                
                usleep(600);
            }
            
        }
        
        len = sprintf(buf,"%x\r\n",sbuf.length);
    
        NSLog(@"%u B",sbuf.length);
        
        llen = sizeof(buf) - len - 4;
        
        if(sbuf.length <= llen){
            memcpy(buf + len, sbuf.data + sbuf.index, sbuf.length);
            len += sbuf.length;
            
            sbuf.index +=  sbuf.length;
            sbuf.length = 0;
        }
        else{
            
            memcpy(buf + len, sbuf.data + sbuf.index, llen);
            
            sbuf.index += llen;
            sbuf.length -= llen;
            
            len += llen;
        }
        
        len += sprintf(buf + len, "\r\n");
       
        if( len != [stream write: (uint8_t *) buf maxLength:len]){
            
            [self didFailError:[stream streamError]];
            
            return NO;
        }

    }
    
    return YES;
}

@end