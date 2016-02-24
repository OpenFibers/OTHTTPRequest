//
//  OTHTTPRequestInputStream.m
//  OTHTTPRequestDemo
//
//  Created by openthread on 2/22/16.
//  Copyright © 2016 openthread. All rights reserved.
//

#import "OTMultipartFormRequestInputStream.h"
#import "OTMultipartFormRequestBodyPart.h"

@interface OTMultipartFormRequestInputStream () <NSStreamDelegate>
@property (nonatomic, readwrite) NSStreamStatus streamStatus;
@property (nonatomic, assign) NSStringEncoding encoding;
@property (nonatomic, strong) NSMutableArray<OTMultipartFormRequestBodyPart *> *formParts;
@property (nonatomic, strong) OTMultipartFormRequestBodyPart *currentReadingBodyPart;
@property (nonatomic, strong) NSEnumerator *HTTPBodyEnumerator;
@end

@implementation OTMultipartFormRequestInputStream
@synthesize streamStatus = _streamStatus;
@synthesize delegate = _delegate;

#pragma mark - Life cycle

- (instancetype)initWithEncoding:(NSStringEncoding)encoding
{
    self = [super init];
    if (self)
    {
        if (encoding == 0 || encoding == 0xffffffff || encoding == NSNotFound)
        {
            self.encoding = NSUTF8StringEncoding;
        }
        self.encoding = encoding;
        self.formParts = [NSMutableArray array];
    }
    return self;
}

- (instancetype)init
{
    self = [self initWithEncoding:NSUTF8StringEncoding];
    return self;
}

- (void)dealloc
{
    
}

#pragma mark - Body part methods

- (unsigned long long)contentLength
{
    unsigned long long totalLength = 0;
    for (OTMultipartFormRequestBodyPart *part in self.formParts)
    {
        totalLength += part.length;
    }
    return totalLength;
}

- (void)setupHTTPBodyWithObjects:(NSArray<OTHTTPRequestPostObject *> *)objects boundary:(NSString *)boundary
{
    if (objects.count == 0)
    {
        return;
    }
    
    OTMultipartFormRequestBodyPart *separatorPart = [self separatorBoundaryPart:boundary];
    
    OTMultipartFormRequestBodyPart *beginPart = [self beginPartWithBoundary:boundary];
    [self.formParts addObject:beginPart];
    
    for (OTHTTPRequestPostObject *eachObject in objects)
    {
        if (eachObject.isFileObject)
        {
            OTMultipartFormRequestBodyPart *headerPart = [self fileHeaderPartWithPostFileObject:eachObject];
            [self.formParts addObject:headerPart];
            
            OTMultipartFormRequestBodyPart *bodyPart = [self fileBodyPartWithPostFileObject:eachObject];
            [self.formParts addObject:bodyPart];
        }
        else
        {
            OTMultipartFormRequestBodyPart *stringParamPart = [self stringParamPartWithPostFileObject:eachObject];
            [self.formParts addObject:stringParamPart];
        }
        
        if (eachObject != objects.lastObject)
        {
            [self.formParts addObject:separatorPart];
        }
    }
    
    OTMultipartFormRequestBodyPart *endPart = [self endBoundaryPart:boundary];
    [self.formParts addObject:endPart];
    
    self.HTTPBodyEnumerator = self.formParts.objectEnumerator;
}

- (OTMultipartFormRequestBodyPart *)beginPartWithBoundary:(NSString *)boundary
{
    NSString *beginBoundary = [NSString stringWithFormat:@"--%@\r\n", boundary];
    OTMultipartFormRequestBodyPart *beginPart = [[OTMultipartFormRequestBodyPart alloc] initWithString:beginBoundary encoding:self.encoding];
    return beginPart;
}

- (OTMultipartFormRequestBodyPart *)separatorBoundaryPart:(NSString *)boundary
{
    NSString *separatorBoundary = [NSString stringWithFormat:@"\r\n--%@\r\n", boundary];
    OTMultipartFormRequestBodyPart *separatorPart = [[OTMultipartFormRequestBodyPart alloc] initWithString:separatorBoundary encoding:self.encoding];
    return separatorPart;
}

- (OTMultipartFormRequestBodyPart *)endBoundaryPart:(NSString *)boundary
{
    NSString *separatorBoundary = [NSString stringWithFormat:@"\r\n--%@--\r\n", boundary];
    OTMultipartFormRequestBodyPart *separatorPart = [[OTMultipartFormRequestBodyPart alloc] initWithString:separatorBoundary encoding:self.encoding];
    return separatorPart;
}

- (OTMultipartFormRequestBodyPart *)stringParamPartWithPostFileObject:(OTHTTPRequestPostObject *)object
{
    NSString *partString = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@", object.key, object.value ?: @""];
    NSData *partData = [partString dataUsingEncoding:self.encoding];
    OTMultipartFormRequestBodyPart *part = [[OTMultipartFormRequestBodyPart alloc] initWithData:partData];
    return part;
}

- (OTMultipartFormRequestBodyPart *)fileHeaderPartWithPostFileObject:(OTHTTPRequestPostObject *)object
{
    if (object.isFileExist)
    {
        NSString *partString = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n", object.key, object.fileName, object.MIMEType];
        NSData *partData = [partString dataUsingEncoding:self.encoding];
        OTMultipartFormRequestBodyPart *part = [[OTMultipartFormRequestBodyPart alloc] initWithData:partData];
        return part;
    }
    return nil;
}

- (OTMultipartFormRequestBodyPart *)fileBodyPartWithPostFileObject:(OTHTTPRequestPostObject *)object
{
    if (object.fileData)
    {
        OTMultipartFormRequestBodyPart *bodyPart = [[OTMultipartFormRequestBodyPart alloc] initWithData:object.fileData];
        return bodyPart;
    }
    else if(object.isFileExist)
    {
        OTMultipartFormRequestBodyPart *bodyPart = [[OTMultipartFormRequestBodyPart alloc] initWithFilePath:object.filePath];
        return bodyPart;
    }
    return nil;
}

#pragma mark - NSInputStream methods

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)length
{
    if ([self streamStatus] == NSStreamStatusClosed)
    {
        return 0;
    }
    NSInteger totalNumberOfBytesRead = 0;
//    while ((NSUInteger)totalNumberOfBytesRead < MIN(length, self.numberOfBytesInPacket))
//    {
//        if (!self.currentHTTPBodyPart || ![self.currentHTTPBodyPart hasBytesAvailable])
//        {
//            if (!(self.currentHTTPBodyPart = [self.HTTPBodyPartEnumerator nextObject]))
//            {
//                break;
//            }
//        }
//        else
//        {
//            NSUInteger maxLength = length - (NSUInteger)totalNumberOfBytesRead;
//            NSInteger numberOfBytesRead = [self.currentHTTPBodyPart read:&buffer[totalNumberOfBytesRead] maxLength:maxLength];
//            if (numberOfBytesRead == -1)
//            {
//                self.streamError = self.currentHTTPBodyPart.inputStream.streamError;
//                break;
//            }
//            else
//            {
//                totalNumberOfBytesRead += numberOfBytesRead;
//            }
//        }
//    }
    return totalNumberOfBytesRead;
}

- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer length:(NSUInteger *)len
{
    return NO;
}

- (BOOL)hasBytesAvailable
{
    return [self streamStatus] == NSStreamStatusOpen;
}

- (void)open
{
    if (self.streamStatus == NSStreamStatusOpen)
    {
        return;
    }
    
    self.streamStatus = NSStreamStatusOpen;
}

- (void)close
{
    self.streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(NSString *)key
{
    return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
    return NO;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
}

@end
