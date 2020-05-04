#2014-02-02
#Pidgin2Mail parses Pidgin HTML chatlogs, and uploads them to an email server.
#Pidgin creates a new log file every time you open a chat window, so many short logs are created if you often close your chat windows.
#This script will merge all files per day, so each contact generates 1 email/day, instead of 1 email per HTML log file. 

#There's 6 classes in this document, sorry. Search for "CONFIG" and adjust as needed.
#It boils down to: a path to output a  log-file. A path to your chat-logs, your user account info for your mail, and you mail server's adress

#Before running it, take a look at your Pidgin log-files. If the content of the <title>-tag doesn't match 
#mine (say, you're running Pidgin in a different language), adjust these in the script too.

# //Ulf Benjaminsson, ulfbenjaminsson.com

package Utils{
	use strict; use warnings;
	sub Utils::getStringBetween{
		#($title) = $str =~ m/ '<title>' (.*) '</title>' /;
		my $str = $_[0];
		my $start = $_[1];
		my $end = $_[2];
		my $startpos = length($start) + index($str, $start);
		my $endpos = index($str, $end, $startpos) - length($str); #rindex($str, $end)
		my $result = substr($str, $startpos, $endpos) or warn Utils::logit("\t\t\tINFO: Error in getStringBetween:\n\t\tStart: '$start'\n\t\tEnd: '$end'\n\t '$str'");
		return $result;
	}
	
	sub log{
		my $message = shift; #($message, $level) = @_;
	}
	
	my $logdir='D:\Dropbox\Applications\PidginPortable\Data\settings\.purple\Pidgin2Mail\\';
	sub Utils::logit
	{
		my $s = shift;
		my $eol = shift;
		$eol = $eol ? $eol : "\n";
		my ($logsec,$logmin,$loghour,$logmday,$logmon,$logyear,$logwday,$logyday,$logisdst)=localtime(time);
		my $logtimestamp = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$logyear+1900,$logmon+1,$logmday,$loghour,$logmin,$logsec);		
		my $logfile = sprintf("%s%4d-%02d-%02d.%s",$logdir,$logyear+1900,$logmon+1,$logmday,'txt');				
		my $fh;
		open($fh, '>>', "$logfile") or warn "$logfile: $!";
			print $fh "$logtimestamp\t $s\n";			
		close($fh);
		print "$logtimestamp\t $s $eol";
		return "$logtimestamp\t $s $eol";
	}
}

#Holds all instances of PidginLogs, sorts them and, optionally, merges them into daily batches.
package LogContainer{
	use strict; use warnings;
	my %_logs = (); 
	my @_hashes = ();
	
	sub new{
		my ($class, %attrs) = @_;		
		bless \%attrs, $class;
	}
	
	sub addLog{
		my ($self, $pidginlog) = @_;		
		my $type = $pidginlog->{chat_protocol};
		my $receiver = $pidginlog->{receiver}; 
		my $sender = $pidginlog->{sender};		
		my $ymd = $pidginlog->{dateTime}->ymd('-'); # yyyy-mm-dd
		my $name = $pidginlog->{name}; # 2007-08-28.130702+0200CEST assumed unique
		my $bucket = "$type $receiver $sender $ymd"; #assuming whitespace will never appear in either of these.
		if(!$_logs{$bucket}){
			$_logs{$bucket} = ();			
			push(@_hashes, $bucket);			
		}
		if($_logs{$bucket}{$name}){
			die Utils::logit("INFO: $name is not unique, at LogContainer::addLog");
		}
		$_logs{$bucket}{$name} = $pidginlog;		
	}
	
	sub merge{
		my $self = shift;
		my $count = $self->getCount();
		Utils::logit("INFO: Starting merge with $count files in ".@_hashes." buckets.");
		@_hashes = sort { lc($a) cmp lc($b) } @_hashes; #sorting hashes, just to keep the logs readable.
		foreach my $bucket(@_hashes){
			my %logs = %{$_logs{$bucket}};			
			my @keys = $self->getSortedKeys($bucket) or next;						
			if(@keys < 2){ next; }			
			Utils::logit(@keys." logs in '$bucket' before merge.");				
			my $first = $logs{shift @keys};						
			foreach my $logname(@keys){				
				$first->appendLogContent($logs{$logname});				
				delete $_logs{$bucket}{$logname};							
			}			
		}	
		$count = $self->getCount();		
		Utils::logit("INFO: Merge completed. There's now $count logs in ".@_hashes." buckets.");
	}
	
	sub getSortedKeys{
		my ($self, $bucket) = @_;					
		return sort { lc($a) cmp lc($b) } keys %{$_logs{$bucket}};				
	}
	
	sub get{
		my ($self, $bucket) = @_;
		my @result = ();
		my @keys = $self->getSortedKeys($bucket) or Utils::logit("INFO: Invalid bucket '$bucket' in ChatLogs::get");
		foreach my $logname(@keys){				
			Utils::logit("INFO: Invalid logname '$logname' in ChatLogs::get ") unless $_logs{$bucket}{$logname};
			push(@result, $_logs{$bucket}{$logname});			
		}		
		return @result;
	}
		
	sub getBuckets{		
		return @_hashes;
	}

	sub getCount{
		my $count = 0;
		foreach my $bucket(@_hashes){
			$count += keys %{$_logs{$bucket}};
		}
		return $count;
	}
}

package PidginLog{
	use strict; use warnings;
	use DateTime::Format::Mail; 
	use DateTime::Format::RFC3501; 
	use feature qw(switch);
	#	CONFIG
	# 		if your Pidgin logs in another language, make sure these match the <title>-tag of your chat logs.
	my $_sep1 = 'Conversation with ';
	my $_sep2 = ' at ';
	my $_sep3 = ' on ';
	my $_sep4 = ' (';
	my $_sep5 = ')';
	# 	CONFIG
	
	my $name; 				#'2007-08-28.121917+0200CEST'
	my $UID;				#an identifier of each file, to ensure we don't parse or submit stuff we've already done.
	my @UIDs;				#identifiers of files that were merged with this log.
	my $rawContent;			#full file content
	my $subject;			#'Conversation with x@x.com at 2007-08-28 12:19:17 on y@y.com (msn)'
	my $body;				#all html between <body>-tags
	my $sender;				#'x@x.com'
	my $timestamp; 			#timestamp from the log text. Inconsistent, and thus - unused. 
	my $receiver;			#'y@y.com'
	my $chat_protocol;      #'msn'
	my $dateTime; 			# DateTime-object. '%Y-%m-%d.%H%M%S%z'  2007-08-28T12:19:17
	my $headertime; 		#'Tue, 28 Aug 2007 12:19:17 +0200'
	my $inboxtime;			#'28-Aug-2007 12:19:17 +0200'
	
	sub new {
		my ($class) = shift;
		my $self  = { @_ };		
		return undef unless defined $self->{name} and defined $self->{rawContent} and defined $self->{dateTime} and defined $self->{UID}; 					
		return undef unless (index($self->{rawContent}, '<title>') >= 0) && (index($self->{rawContent}, '</title>') >= 0); #if the file holds bad content. This happens. 
		$self->{headertime} 	= DateTime::Format::Mail->format_datetime($self->{dateTime}); #RFC2822
		$self->{inboxtime} 		= DateTime::Format::RFC3501->format_datetime($self->{dateTime}); 
		$self->{subject} 		= Utils::getStringBetween($self->{rawContent},'<title>','</title>');		
		$self->{sender} 		= Utils::getStringBetween($self->{subject}, $_sep1, $_sep2);
		#$self->{timestamp} 	= Utils::getStringBetween($title, $_sep2, $_sep3); #unused, since it's inconsistent
		$self->{receiver} 		= Utils::getStringBetween($self->{subject}, $_sep3, $_sep4);
		$self->{chat_protocol} 	= Utils::getStringBetween($self->{subject}, $_sep4, $_sep5);
		$self->{body} 			= substr($self->{rawContent}, index($self->{rawContent}, '<body>')); #slurp up everything else.
		my $find = quotemeta('</body>'); #cause sometimes Pidgin forgot to add the closing body tag.
		$self->{body} =~ s/$find//g; #let's remove it if it's there. 		
		$self->{UIDs}			= [$self->{UID}];
		delete $self->{rawContent};				
		return bless $self, $class; 
	}
		
	sub getMailHeaders{
		my $self = shift;
		my $headers = "From: $self->{sender}\r\n";
		$headers .= "To: $self->{receiver}\r\n";	
		$headers .= "Subject: $self->{subject}\r\n";
		$headers .= "Date: $self->{headertime}\r\n";
		$headers .= "MIME-Version: 1.0\r\n";
		$headers .= "Content-Type: text/html; charset=UTF-8\r\n"; #"Content-Type: text/html; charset=iso-8859-1\r\n";
		return $headers;
	}
	
	sub getHTMLBody{ 
		my $self = shift;
		return '<body>'.$self->{body}.'</body>';
	}

	sub getUIDs{
		my $self = shift;
		return $self->{UIDs};
	}
	sub appendLogContent{
		my ($self, $pidginlog) = @_;	
		die Utils::logit("\tINFO: Attempted merge of logs from different senders") 	unless $self->{sender} eq $pidginlog->{sender};
		die Utils::logit("\tINFO: Attempted merge of logs to different accounts") 	unless $self->{receiver} eq $pidginlog->{receiver};
		die Utils::logit("\tINFO: Attempted merge of logs from different networks") unless $self->{chat_protocol} eq $pidginlog->{chat_protocol};
		die Utils::logit("\tINFO: Attempted unsorted merge of logs") 				unless (DateTime->compare($pidginlog->{dateTime}, $self->{dateTime}) > 0);		
		Utils::logit("\tAppending: $pidginlog->{name}");
		$self->{body} .= "\n\n".$pidginlog->{body};			
		push($self->{UIDs}, $pidginlog->{UID});
	}
}

package IMAPHelper{
	use strict;	use warnings;
	use Net::SSLeay;
	use Mail::IMAPClient;	
	use IO::Socket::SSL;
	use DateTime::Format::Strptime;	

	##CONFIGS			
	my $_markAsRead = 1; #mark all synced logs as read in inbox.	
	##CONFIGS

	##MEMBERS
	my $_imap = undef;
	my $_sep = ''; 			# folder hierarchy separator character	
	my $_baseFolder = ''; 	
	my $_currentFolder = ''; 
	my $_port = '';
	my $_server = ''; 	
	
	sub new{
		my ($class, %attrs) = @_;		
		$_port = $attrs{'port'};
		$_server = $attrs{'server'};
		bless \%attrs, $class;
	}
	sub DESTROY {
		my $self = shift;
		if($_imap){
			$self->disconnect();
		}
	}
	sub connect{
		my ($self, $user, $password, $basefolder) = @_;
		if($_imap){
			die "\n\tError: connecting twice on same socket";
		}
		Utils::logit("Logging in '$user'.");
		my $socket = IO::Socket::SSL->new(  
		   PeerAddr =>  $_server,  
		   PeerPort =>  $_port, 
		   SSL_verify_mode => 'SSL_VERIFY_NONE'
		)  
		or die "socket(): $@";  
		$_imap = Mail::IMAPClient->new(
			User     => $user,
			Password => $password,
			socket => $socket,
			Uid => 1,
		) or die ($_imap);
		$_imap->IsAuthenticated() or die Utils::logit("\tINFO: Couldn't Authenticate!");
		$_sep = $_imap->separator; 						# Get folder hierarchy separator character
		$_baseFolder = $basefolder;
		if($_imap->is_parent("INBOX")){ 	# Find out if server accepts subfolders inside INBOX:
			$_baseFolder = "INBOX".$_sep.$_baseFolder; # I'm not sure if this is needed or wanted - it was in the imap demo code so I kept it.
		}
		$_currentFolder	= $_baseFolder;
	}
	
	sub disconnect{
		Utils::logit("Logging out.");
		$_imap->logout or die Utils::logit("INFO: Logout error: ". $_imap->LastError);
		$_imap = undef;
	}	
		
	sub selectFolder{
		my ($self, @folders) = @_;		
		my $find = quotemeta($_sep);
		foreach my $a(@folders){			
			$a =~ s/$find/-/g; #replace the separator if it's used in either of the folders.
		}	
		unshift(@folders, $_baseFolder);		
		my $fullPath = join($_sep, @folders);		
		#Utils::logit("DRYRUN: Selecting '$fullPath'.");		
		if(!$_imap->exists($fullPath)){	#create folder structure, level by level.		
			my $folder = '';
			foreach my $label (@folders){
				$folder .= $label;
				unless($_imap->exists($folder)){
					Utils::logit("Creating '$folder'");
					if(!$_imap->create($folder)){
						Utils::logit("\tINFO: Cannot create '$folder'. Server says: ". $_imap->LastError);						
						return undef;
					}
				}
				$folder .= $_sep;
			}
			$fullPath = substr($folder, 0, rindex($folder, $_sep)); #remove trailing separator
		}
		if(!$_imap->select($fullPath)){			
			Utils::logit("\tINFO: Cannot select '$fullPath'. Server says: ". $_imap->LastError);
			return undef;
		}		
		$_currentFolder	= $fullPath;
		return 1;
	}
	
	sub submit{				
		my ($self, $mailheaders, $htmlbody, $inboxtime) = @_;	
		#return ($self && $mailheaders && $htmlbody && $inboxtime);	#DRYRUN
		my $uidort = $_imap->append_string($_currentFolder, $mailheaders."
		
		".$htmlbody, ($_markAsRead) ? '\Seen' : undef, $inboxtime) 
			or warn Utils::logit("INFO: Could not submit mail. Server says: ". $_imap->LastError);
	
		return defined($uidort);
	}

}
	
package Pidgin2Mail{
	use strict; use warnings;
	use Net::SSLeay;	
	use File::Find;	
	use DateTime::Format::Strptime;	
	
	##CONFIGS
	my $_logFolder = 'D:\Dropbox\Applications\PidginPortable\Data\settings\.purple\logs\\';
	my $_pathLength = length($_logFolder)-length('\sample-data\\'); #for easy substr and cleaner logging.
	my $_log_file_ext = 'html';	
	my $_baseFolder = 'Pidgin'; 		#what label do you want to sort chats under? ('Chats' is reserved)
	my $_user = 'username@gmail.com'; 	# username@gmail.com
	my $_password = '';	#use an application specific password, please. http://goo.gl/aCQAx6		
	##MEMBERS
	my %_previousRun;	
	my $_chatLogs = undef;
	my $_dirCount = my $_fileCount = 0;
	
	sub getFileContent {		
		my $fh;		
		if(!open($fh, "<", $File::Find::name)){
			my $nicename = substr($File::Find::name, $_pathLength);
			warn Utils::logit("INFO: Couldn't open $nicename: $!");
			return undef;
		}
		my $contents = undef;		
		{ 
			local $/ = undef;     # Read entire file at once
			$contents = <$fh>;    # Return file as one single `line'
		}
		close $fh;
		return $contents;
	}
	
	sub filter{
		my $nicename = substr($File::Find::dir, $_pathLength);
		my @clean;		
		my $filecount = my $dircount = 0;
		foreach(@_){						
			next unless -R $_;	#unless readable						
			next unless -f _ || -d _; #unless file or dir.
			next if ($_ =~ m/^\./); #ignore files/folders beginning with a period
			if(-f _){ #regular file				
				next unless (my $size = -s _); #does it have a size?
				next unless ($_ =~ m/([^.]+)$/)[0] eq $_log_file_ext; #correct file extension?
				next if exists($_previousRun{$_." ($size)"}); #don't add files we've already processed
				$filecount++;				
			}elsif(-d _){ #dir
				$dircount++;
			}
			push(@clean, $_);			
		}
		$_fileCount += $filecount;
		$_dirCount += $dircount;
		Utils::logit("'$nicename' contains $filecount new files and $dircount folders to explore.");
		return @clean;
	}
	
	sub readFile {			
		return unless -f $_; #don't read directories						
		my $size = -s _;
		return unless my $content = getFileContent($_);
		return unless my $dateTime = filenameToDateTime($_);		
		my $log = new PidginLog(
			name 		=> substr($_, 0, rindex($_, '.')), #name without file ending
			UID 		=> $_ ." ($size)", #adding (size in bytes) to filename, to make collisions very unlikely.
			rawContent 	=> $content, 
			dateTime 	=> $dateTime
		);
		if(!$log){
			Utils::logit("\tINFO: $_ seems broken. Ignoring.");
		}else{
			$_chatLogs->addLog($log);
		}
	}
	
	#takes pidgin logfilename (incl. file extension): '2008-11-07.171101+0100CET.html'
	#an RFC-822 date-time
	sub filenameToDateTime{ 
		my $filename = shift;
		my $clean = substr($filename, 0, rindex($filename, '.')); 	#strip file ending
		#$clean = substr($filename, 0, rindex($filename, '+')); 	#strip timezone
		#$clean =~ s/\./T/; #replace dot with T for time separation
		my $strp = DateTime::Format::Strptime->new(
		   pattern => '%Y-%m-%d.%H%M%S%z' #ignore timezone name %Z, since this buggers out when Pidgin has been stupid (eg: +2ECT, which should be +2ECST)
		);
		my $datetime = $strp->parse_datetime($clean);
		if(!$datetime){
			warn Utils::logit("INFO: Unable to parse datetime from filename: $filename");	
			return undef;
		}		
		return $datetime;
	}

	sub main{			
		dbmopen(%_previousRun,$_logFolder,0666) or die("Couldn't create history-file!");		
		my $start = time();
		$_chatLogs = new LogContainer;
		File::Find::find({wanted => \&readFile, preprocess => \&filter}, $_logFolder);												
		$_chatLogs->merge();	
		my $count = $_chatLogs->getCount();
		my $gmail = new IMAPHelper('port' => '993', 'server' => 'imap.gmail.com');			
		$gmail->connect($_user, $_password, $_baseFolder);		
		my @buckets = $_chatLogs->getBuckets(); #buckets are sorted!
		my $currentFolders = 'mingegurgle';
		foreach my $bucket(@buckets){ # $bucket = "$type $receiver $sender $ymd"										
			if(index($bucket, $currentFolders) != 0){ #only call selectFolder when we move into a new folder.
				my($protocol, $receiver, $rest) = split(" ", $bucket, 3);			
				$gmail->selectFolder(($protocol, $receiver)) or next;
				$currentFolders = "$protocol $receiver"; 				
			}			
			foreach my $pidginlog ($_chatLogs->get($bucket)){
				Utils::logit("\tSubmitting... $count","\r\n");
				if($gmail->submit($pidginlog->getMailHeaders(), $pidginlog->getHTMLBody(), $pidginlog->{inboxtime})){					
					foreach my $uid (@{$pidginlog->{UIDs}}){ #add all UID to the list.						
						$_previousRun{$uid} = 1;
					}					
					$count--;				
				}else{
					Utils::logit("INFO: Unable to submit " . $pidginlog->{name} ."!");					
				}
			}			
		}
		Utils::logit("INFO: $count logfiles left to submit! Check output and see if anything caused problems.");				
		$gmail->disconnect();				
		dbmclose(%_previousRun);				
		my $run_time = time() - $start;
		Utils::logit("INFO: Processed $_fileCount files in $_dirCount folders in...");				
		Utils::logit("INFO:\t". int($run_time /(24*60*60)) ."days " . ($run_time/(60*60))%24 . "hours " . ($run_time /60)%60 . "mins " . $run_time%60 . "secs");		
		return 0;
	}	
	exit(main(@ARGV));
};
