/*
 * MailCore
 *
 * Copyright (C) 2007 - Matt Ronge
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the MailCore project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#import "CTCoreMessage.h"
#import "CTCoreFolder.h"
#import "MailCoreTypes.h"
#import "CTCoreAddress.h"
#import "CTMIMEFactory.h"
#import "CTMIME_MessagePart.h"
#import "CTMIME_TextPart.h"
#import "CTMIME_MultiPart.h"
#import "CTMIME_SinglePart.h"
#import "CTBareAttachment.h"

@interface CTCoreMessage (Private)
- (CTCoreAddress *)_addressFromMailbox:(struct mailimf_mailbox *)mailbox;
- (NSSet *)_addressListFromMailboxList:(struct mailimf_mailbox_list *)mailboxList;
- (struct mailimf_mailbox_list *)_mailboxListFromAddressList:(NSSet *)addresses;
- (NSSet *)_addressListFromIMFAddressList:(struct mailimf_address_list *)imfList;
- (struct mailimf_address_list *)_IMFAddressListFromAddresssList:(NSSet *)addresses;
- (void)_buildUpBodyText:(CTMIME *)mime result:(NSMutableString *)result;
- (void)_buildUpHtmlBodyText:(CTMIME *)mime result:(NSMutableString *)result;
- (NSString *)_decodeMIMEPhrase:(char *)data;
@end

//TODO Add encode of subjects/from/to
//TODO Add decode of to/from ...
/*
char * etpan_encode_mime_header(char * phrase)
{
  return
    etpan_make_quoted_printable(DEFAULT_DISPLAY_CHARSET,
        phrase);
}
*/

@implementation CTCoreMessage
@synthesize mime=myParsedMIME;

- (id)init {
	[super init];
	if (self) {
		struct mailimf_fields *fields = mailimf_fields_new_empty();
		myFields = mailimf_single_fields_new(fields);
		mailimf_fields_free(fields);
	}
	return self;
}


- (id)initWithMessageStruct:(struct mailmessage *)message {
	self = [super init];
	if (self) {
		assert(message != NULL);
		myMessage = message;
		myFields = mailimf_single_fields_new(message->msg_fields);
	}
	return self;
}

- (id)initWithFileAtPath:(NSString *)path {
	return [self initWithString:[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]];
}

- (id)initWithString:(NSString *)msgData {
   	struct mailmessage *msg = data_message_init((char *)[msgData cStringUsingEncoding:NSUTF8StringEncoding], 
									[msgData lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
	int err;
	struct mailmime *dummyMime;
	/* mailmessage_get_bodystructure will fill the mailmessage struct for us */
	err = mailmessage_get_bodystructure(msg, &dummyMime);
	assert(err == 0);
	return [self initWithMessageStruct:msg];
}


- (void)dealloc {
	if (myMessage != NULL) {
		mailmessage_flush(myMessage);
		mailmessage_free(myMessage);
	}
	if (myFields != NULL) {
		mailimf_single_fields_free(myFields);
	}
	[myParsedMIME release];
	[super dealloc];
}



- (int)fetchBody {
	int err;
	struct mailmime *dummyMime;
	//Retrieve message mime and message field
	err = mailmessage_get_bodystructure(myMessage, &dummyMime);
	if(err != 0) { // added by gabor
		return err;
	}
	myParsedMIME = [[CTMIMEFactory createMIMEWithMIMEStruct:[self messageStruct]->msg_mime 
						forMessage:[self messageStruct]] retain];
	
	return 0;
}


- (NSString *)body {
	NSMutableString *result = [NSMutableString string];
	[self _buildUpBodyText:myParsedMIME result:result];
	return result;
}

- (NSString *)htmlBody {
	// added by Gabor
	NSMutableString *result = [NSMutableString string];
	[self _buildUpHtmlBodyText:myParsedMIME result:result];
	return result;
}

- (NSString *)bodyPreferringPlainText {
    NSString *body = [self body];
    if ([body length] == 0) {
        body = [self htmlBody];
    }
    return body;
}


- (void)_buildUpBodyText:(CTMIME *)mime result:(NSMutableString *)result {
	if (mime == nil)
		return;
	
	if ([mime isKindOfClass:[CTMIME_MessagePart class]]) {
		[self _buildUpBodyText:[mime content] result:result];
	}
	else if ([mime isKindOfClass:[CTMIME_TextPart class]]) {
		if ([mime.contentType isEqualToString:@"text/plain"]) {
			[(CTMIME_TextPart *)mime fetchPart];
			NSString* y = [mime content];
			if(y != nil) {
				[result appendString:y];
			}
		}
	}
	else if ([mime isKindOfClass:[CTMIME_MultiPart class]]) {
		//TODO need to take into account the different kinds of multipart
		NSEnumerator *enumer = [[mime content] objectEnumerator];
		CTMIME *subpart;
		while ((subpart = [enumer nextObject])) {
			[self _buildUpBodyText:subpart result:result];
		}
	}
}

- (void)_buildUpHtmlBodyText:(CTMIME *)mime result:(NSMutableString *)result {
	if (mime == nil)
		return;
	
	if ([mime isKindOfClass:[CTMIME_MessagePart class]]) {
		[self _buildUpHtmlBodyText:[mime content] result:result];
	}
	else if ([mime isKindOfClass:[CTMIME_TextPart class]]) {
		if ([mime.contentType isEqualToString:@"text/html"]) {
			[(CTMIME_TextPart *)mime fetchPart];
			NSString* y = [mime content];
			if(y != nil) {
				[result appendString:y];
			}
		}
	}
	else if ([mime isKindOfClass:[CTMIME_MultiPart class]]) {
		//TODO need to take into account the different kinds of multipart
		NSEnumerator *enumer = [[mime content] objectEnumerator];
		CTMIME *subpart;
		while ((subpart = [enumer nextObject])) {
			[self _buildUpHtmlBodyText:subpart result:result];
		}
	}
}


- (void)setBody:(NSString *)body {
	CTMIME *oldMIME = myParsedMIME;
	CTMIME_TextPart *text = [CTMIME_TextPart mimeTextPartWithString:body];
	
	// If myParsedMIME is already a multi-part mime, just add it. otherwise replace it.
    //TODO: If setBody is called multiple times it will add text parts multiple times. Instead
    // it should find the existing text part (if there is one) and replace it
	if ([myParsedMIME isKindOfClass:[CTMIME_MultiPart class]]) {
		[(CTMIME_MultiPart *)myParsedMIME addMIMEPart:text];
	} else {
		CTMIME_MessagePart *messagePart = [CTMIME_MessagePart mimeMessagePartWithContent:text];
		myParsedMIME = [messagePart retain];
		[oldMIME release];		
	}
}

- (NSArray *)attachments {
	NSMutableArray *attachments = [NSMutableArray array];

	CTMIME_Enumerator *enumerator = [myParsedMIME mimeEnumerator];
	CTMIME *mime;
	while ((mime = [enumerator nextObject])) {
		if ([mime isKindOfClass:[CTMIME_SinglePart class]]) {
			CTMIME_SinglePart *singlePart = (CTMIME_SinglePart *)mime;
			if (singlePart.attached) {
				CTBareAttachment *attach = [[CTBareAttachment alloc] 
												initWithMIMESinglePart:singlePart];
				[attachments addObject:attach];
				[attach release];
			}
		}
	}
	return attachments;
}

- (void)addAttachment:(CTCoreAttachment *)attachment {
	CTMIME_MultiPart *multi;
	CTMIME_MessagePart *msg;
	
	if ([myParsedMIME isKindOfClass:[CTMIME_MessagePart class]]) {
		msg = (CTMIME_MessagePart *)myParsedMIME;
		CTMIME *sub = [msg content];
		
		
		// Creat new multimime part if needed
		if ([sub isKindOfClass:[CTMIME_MultiPart class]]) {
			multi = (CTMIME_MultiPart *)sub;
		} else {
			multi = [CTMIME_MultiPart mimeMultiPart];
			[multi addMIMEPart:sub];
			[msg setContent:multi];
		}
		
		// add new SinglePart which encodes the attachment in base64
		CTMIME_SinglePart *attpart = [CTMIME_SinglePart mimeSinglePartWithData:[attachment data]];
		attpart.contentType = [attachment contentType];
		attpart.filename = [attachment filename];
	
		[multi addMIMEPart:attpart];
	}
}


- (NSString *)subject {
	if (myFields->fld_subject == NULL)
		return @"";
	NSString *decodedSubject = [self _decodeMIMEPhrase:myFields->fld_subject->sbj_value];
	if (decodedSubject == nil)
		return @"";
	return decodedSubject;
}


- (void)setSubject:(NSString *)subject {
	struct mailimf_subject *subjectStruct;
	
	subjectStruct = mailimf_subject_new(strdup([subject cStringUsingEncoding:NSUTF8StringEncoding]));
	if (myFields->fld_subject != NULL)
		mailimf_subject_free(myFields->fld_subject);
	myFields->fld_subject = subjectStruct;
}

- (struct mailimf_date_time*)libetpanDateTime {    
    if(!myFields || !myFields->fld_orig_date || !myFields->fld_orig_date->dt_date_time)
        return NULL;
    
    return myFields->fld_orig_date->dt_date_time;
}

- (NSTimeZone*)senderTimeZone {
    struct mailimf_date_time *d;
    
    if((d = [self libetpanDateTime]) == NULL)
        return nil;
    
    NSInteger timezoneOffsetInSeconds = 3600*d->dt_zone/100;
    
    return [NSTimeZone timeZoneForSecondsFromGMT:timezoneOffsetInSeconds];
}

- (NSDate *)senderDate {
    
  	if ( myFields->fld_orig_date == NULL) {
    	return [NSDate distantPast];
	}
  	else {
        struct mailimf_date_time *d;
        
        if((d = [self libetpanDateTime]) == NULL)
            return nil;
        
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        NSDateComponents *comps = [[NSDateComponents alloc] init];
        
        [comps setYear:d->dt_year];
        [comps setMonth:d->dt_month];
        [comps setDay:d->dt_day];
        [comps setHour:d->dt_hour];
        [comps setMinute:d->dt_min];
        [comps setSecond:d->dt_sec];
        
        NSDate *messageDateNoTimezone = [calendar dateFromComponents:comps];
        
        [comps release];
        [calendar release];
        
        // no timezone applied
        return messageDateNoTimezone;
  	}
}

- (NSDate *)sentDateGMT {
    struct mailimf_date_time *d;
    
    if((d = [self libetpanDateTime]) == NULL)
        return nil;
    
    NSInteger timezoneOffsetInSeconds = 3600*d->dt_zone/100;
    
    NSDate *date = [self senderDate];

    return [date dateByAddingTimeInterval:timezoneOffsetInSeconds * -1];
}

- (NSDate*)sentDateLocalTimeZone {
    return [[self sentDateGMT] dateByAddingTimeInterval:[[NSTimeZone localTimeZone] secondsFromGMT]];
}

- (BOOL)isUnread {
	struct mail_flags *flags = myMessage->msg_flags;
	if (flags != NULL) {
		BOOL flag_seen = (flags->fl_flags & MAIL_FLAG_SEEN);
		return !flag_seen;
	}
	return NO;
}

- (BOOL)isNew {
	struct mail_flags *flags = myMessage->msg_flags;
	if (flags != NULL) {
		BOOL flag_seen = (flags->fl_flags & MAIL_FLAG_SEEN);
		BOOL flag_new = (flags->fl_flags & MAIL_FLAG_NEW);
		return !flag_seen && flag_new;
	}
	return NO;
}

- (NSString *)messageId {
  	if (myFields->fld_message_id != NULL) {
        char *value = myFields->fld_message_id->mid_value;
        return [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
	}
    return nil;
}

- (NSString *)uid {
	return [NSString stringWithCString:myMessage->msg_uid encoding:NSUTF8StringEncoding];
}

- (NSUInteger)messageSize {
	return [self messageStruct]->msg_size;
}

- (NSUInteger)sequenceNumber {
	return mySequenceNumber;
}

- (void)setSequenceNumber:(NSUInteger)sequenceNumber {
	mySequenceNumber = sequenceNumber;
}


- (NSSet *)from {
	if (myFields->fld_from == NULL)
		return [NSSet set]; //Return just an empty set

	return [self _addressListFromMailboxList:myFields->fld_from->frm_mb_list];
}


- (void)setFrom:(NSSet *)addresses {
	struct mailimf_mailbox_list *imf = [self _mailboxListFromAddressList:addresses];
	if (myFields->fld_from != NULL)
		mailimf_from_free(myFields->fld_from);
	myFields->fld_from = mailimf_from_new(imf);	
}


- (CTCoreAddress *)sender {
	if (myFields->fld_sender == NULL)
		return [CTCoreAddress address];
		
	return [self _addressFromMailbox:myFields->fld_sender->snd_mb];
}


- (NSSet *)to {
	if (myFields->fld_to == NULL)
		return [NSSet set];
	else
		return [self _addressListFromIMFAddressList:myFields->fld_to->to_addr_list];
}


- (void)setTo:(NSSet *)addresses {
	struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
	
	if (myFields->fld_to != NULL) {
		mailimf_address_list_free(myFields->fld_to->to_addr_list);
		myFields->fld_to->to_addr_list = imf;
	}
	else
		myFields->fld_to = mailimf_to_new(imf);
}


- (NSSet *)cc {
	if (myFields->fld_cc == NULL)
		return [NSSet set];
	else
		return [self _addressListFromIMFAddressList:myFields->fld_cc->cc_addr_list];
}


- (void)setCc:(NSSet *)addresses {
	struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
	if (myFields->fld_cc != NULL) {
		mailimf_address_list_free(myFields->fld_cc->cc_addr_list);
		myFields->fld_cc->cc_addr_list = imf;
	}
	else
		myFields->fld_cc = mailimf_cc_new(imf);
}


- (NSSet *)bcc {
	if (myFields->fld_bcc == NULL)
		return [NSSet set];
	else
		return [self _addressListFromIMFAddressList:myFields->fld_bcc->bcc_addr_list];
}


- (void)setBcc:(NSSet *)addresses {
	struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
	if (myFields->fld_bcc != NULL) {
		mailimf_address_list_free(myFields->fld_bcc->bcc_addr_list);
		myFields->fld_bcc->bcc_addr_list = imf;
	}
	else
		myFields->fld_bcc = mailimf_bcc_new(imf);
}


- (NSSet *)replyTo {
	if (myFields->fld_reply_to == NULL)
		return [NSSet set];
	else
		return [self _addressListFromIMFAddressList:myFields->fld_reply_to->rt_addr_list];
}


- (void)setReplyTo:(NSSet *)addresses {
	struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
	if (myFields->fld_reply_to != NULL) {
		mailimf_address_list_free(myFields->fld_reply_to->rt_addr_list);
		myFields->fld_reply_to->rt_addr_list = imf;
	}
	else
		myFields->fld_reply_to = mailimf_reply_to_new(imf);
}

- (void)setOptionalHeader:(NSString*)name value:(NSString*)value {
    if (!optionalHeaders) {
        optionalHeaders = [[NSMutableArray alloc] init];
    }

    struct mailimf_optional_field *opt = mailimf_optional_field_new((char*)[name cStringUsingEncoding:NSASCIIStringEncoding],
                                                                    (char*)[value cStringUsingEncoding:NSASCIIStringEncoding]);

    struct mailimf_field *field = mailimf_field_new(MAILIMF_FIELD_OPTIONAL_FIELD,
                                                    NULL, NULL, NULL, NULL,
                                                    NULL, NULL, NULL, NULL,
                                                    NULL, NULL, NULL, NULL,
                                                    NULL, NULL, NULL, NULL,
                                                    NULL, NULL, NULL, NULL,
                                                    NULL, opt);
    [optionalHeaders addObject:[NSValue valueWithPointer:field]];
}

- (NSString *)render {
	CTMIME *msgPart = myParsedMIME;

	if ([myParsedMIME isKindOfClass:[CTMIME_MessagePart class]]) {
		/* It's a message part, so let's set it's fields */
		struct mailimf_fields *fields;
		struct mailimf_mailbox *sender = (myFields->fld_sender != NULL) ? (myFields->fld_sender->snd_mb) : NULL;
		struct mailimf_mailbox_list *from = (myFields->fld_from != NULL) ? (myFields->fld_from->frm_mb_list) : NULL;
		struct mailimf_address_list *replyTo = (myFields->fld_reply_to != NULL) ? (myFields->fld_reply_to->rt_addr_list) : NULL;
		struct mailimf_address_list *to = (myFields->fld_to != NULL) ? (myFields->fld_to->to_addr_list) : NULL;
		struct mailimf_address_list *cc = (myFields->fld_cc != NULL) ? (myFields->fld_cc->cc_addr_list) : NULL;
		struct mailimf_address_list *bcc = (myFields->fld_bcc != NULL) ? (myFields->fld_bcc->bcc_addr_list) : NULL;
		clist *inReplyTo = (myFields->fld_in_reply_to != NULL) ? (myFields->fld_in_reply_to->mid_list) : NULL;
		clist *references = (myFields->fld_references != NULL) ? (myFields->fld_references->mid_list) : NULL;
		char *subject = (myFields->fld_subject != NULL) ? (myFields->fld_subject->sbj_value) : NULL;
		
		//TODO uh oh, when this get freed it frees stuff in the CTCoreMessage
		//TODO Need to make sure that fields gets freed somewhere
		fields = mailimf_fields_new_with_data(from, sender, replyTo, to, cc, bcc, inReplyTo, references, subject);
        for (NSValue *v in optionalHeaders) {
            clist_append(fields->fld_list, [v pointerValue]);
        }
		[(CTMIME_MessagePart *)msgPart setIMFFields:fields];
	}
	return [myParsedMIME render];
}

- (NSData *)messageAsEmlx {
    NSString *msgContent = [[self rfc822] stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSData *msgContentAsData = [msgContent dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *emlx = [NSMutableData data];
    [emlx appendData:[[NSString stringWithFormat:@"%-10d\n", msgContentAsData.length] dataUsingEncoding:NSUTF8StringEncoding]];
    [emlx appendData:msgContentAsData];


	struct mail_flags *flagsStruct = myMessage->msg_flags;
    long long flags = 0;
	if (flagsStruct != NULL) {
        BOOL seen = (flagsStruct->fl_flags & CTFlagSeen) > 0;
		flags |= seen << 0;
        BOOL answered = (flagsStruct->fl_flags & CTFlagAnswered) > 0;
		flags |= answered << 2;
        BOOL flagged = (flagsStruct->fl_flags & CTFlagFlagged) > 0;
		flags |= flagged << 4;
        BOOL forwarded = (flagsStruct->fl_flags & CTFlagForwarded) > 0;
		flags |= forwarded << 8;
    }

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setValue:[NSNumber numberWithDouble:[[self senderDate] timeIntervalSince1970]] forKey:@"date-sent"];
    [dictionary setValue:[NSNumber numberWithUnsignedLongLong:flags] forKey:@"flags"];
    [dictionary setValue:[self subject] forKey:@"subject"];

    NSError *error;
    NSData *propertyList = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                                      format:NSPropertyListXMLFormat_v1_0
                                                                     options:0
                                                                       error:&error];
    [emlx appendData:propertyList];
    return emlx;
}

- (NSString *)rfc822 {
    char *result = NULL;
    NSString *nsresult;
    int r = mailimap_fetch_rfc822([self imapSession], [self sequenceNumber], &result);
    if (r == 0) {
        nsresult = [[NSString alloc] initWithCString:result encoding:NSUTF8StringEncoding];
    } else {
		NSException *exception = [NSException
			        exceptionWithName:CTUnknownError
			        reason:[NSString stringWithFormat:@"Error number: %d",r]
			        userInfo:nil];
		[exception raise];
    }
    mailimap_msg_att_rfc822_free(result);
    return [nsresult autorelease];
}


- (struct mailmessage *)messageStruct {
	return myMessage;
}

- (mailimap *)imapSession; {
	struct imap_cached_session_state_data * cached_data;
	struct imap_session_state_data * data;
	mailsession *session = [self messageStruct]->msg_session;

	if (strcasecmp(session->sess_driver->sess_name, "imap-cached") == 0) {
    	cached_data = session->sess_data;
    	session = cached_data->imap_ancestor;
  	}

	data = session->sess_data;
	return data->imap_session;	
}

/*********************************** myprivates ***********************************/
- (CTCoreAddress *)_addressFromMailbox:(struct mailimf_mailbox *)mailbox; {
	CTCoreAddress *address = [CTCoreAddress address];
	if (mailbox == NULL) {
		return address;
    }
	if (mailbox->mb_display_name != NULL) {
		NSString *decodedName = [self _decodeMIMEPhrase:mailbox->mb_display_name];
		if (decodedName == nil) {
			decodedName = @"";
        }
		[address setName:decodedName];
	}
	if (mailbox->mb_addr_spec != NULL) {
		[address setEmail:[NSString stringWithCString:mailbox->mb_addr_spec encoding:NSUTF8StringEncoding]];
    }
	return address;
}


- (NSSet *)_addressListFromMailboxList:(struct mailimf_mailbox_list *)mailboxList; {
	clist *list;
	clistiter * iter;
	struct mailimf_mailbox *address;
	NSMutableSet *addressSet = [NSMutableSet set];
	
	if (mailboxList == NULL)
		return addressSet;
		
	list = mailboxList->mb_list;
	for(iter = clist_begin(list); iter != NULL; iter = clist_next(iter)) {
    	address = clist_content(iter);
		[addressSet addObject:[self _addressFromMailbox:address]];
  	}
	return addressSet;
}


- (struct mailimf_mailbox_list *)_mailboxListFromAddressList:(NSSet *)addresses {
	struct mailimf_mailbox_list *imfList = mailimf_mailbox_list_new_empty();
	NSEnumerator *objEnum = [addresses objectEnumerator];
	CTCoreAddress *address;
	int err;
	const char *addressName;
	const char *addressEmail;

	while(address = [objEnum nextObject]) {
		addressName = [[address name] cStringUsingEncoding:NSUTF8StringEncoding];
		addressEmail = [[address email] cStringUsingEncoding:NSUTF8StringEncoding];
		err =  mailimf_mailbox_list_add_mb(imfList, strdup(addressName), strdup(addressEmail));
		assert(err == 0);
	}
	return imfList;	
}


- (NSSet *)_addressListFromIMFAddressList:(struct mailimf_address_list *)imfList {
	clist *list;
	clistiter * iter;
	struct mailimf_address *address;
	NSMutableSet *addressSet = [NSMutableSet set];
	
	if (imfList == NULL)
		return addressSet;
		
	list = imfList->ad_list;
	for(iter = clist_begin(list); iter != NULL; iter = clist_next(iter)) {
    	address = clist_content(iter);
		/* Check to see if it's a solo address a group */
		if (address->ad_type == MAILIMF_ADDRESS_MAILBOX) {
			[addressSet addObject:[self _addressFromMailbox:address->ad_data.ad_mailbox]];
		}
		else {
			if (address->ad_data.ad_group->grp_mb_list != NULL)
				[addressSet unionSet:[self _addressListFromMailboxList:address->ad_data.ad_group->grp_mb_list]];
		}
  	}
	return addressSet;
}


- (struct mailimf_address_list *)_IMFAddressListFromAddresssList:(NSSet *)addresses {
	struct mailimf_address_list *imfList = mailimf_address_list_new_empty();
	
	NSEnumerator *objEnum = [addresses objectEnumerator];
	CTCoreAddress *address;
	int err;
	const char *addressName;
	const char *addressEmail;

	while(address = [objEnum nextObject]) {
		addressName = [[address name] cStringUsingEncoding:NSUTF8StringEncoding];
		addressEmail = [[address email] cStringUsingEncoding:NSUTF8StringEncoding];
		err =  mailimf_address_list_add_mb(imfList, strdup(addressName), strdup(addressEmail));
		assert(err == 0);
	}
	return imfList;
}

- (NSString *)_decodeMIMEPhrase:(char *)data {
	int err;
	size_t currToken = 0;
	char *decodedSubject;
	NSString *result;
	
	if (*data != '\0') {
		err = mailmime_encoded_phrase_parse(DEST_CHARSET, data, strlen(data),
			&currToken, DEST_CHARSET, &decodedSubject);
			
		if (err != MAILIMF_NO_ERROR) {
			if (decodedSubject == NULL)
				free(decodedSubject);
			return nil;
		}
	}
	else {
		return @"";
	}
		
	result = [NSString stringWithCString:decodedSubject encoding:NSUTF8StringEncoding];
	free(decodedSubject);
	return result;
}

@end
