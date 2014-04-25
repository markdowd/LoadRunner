#!/usr/bin/perl -w
#######################################################################
# Name:		lr_scenario.pl
# Author:	Mark Dowd
# Copyright:	Mark Dowd (c) 2014
# Purpose:	Extract key data from a LoadRunner scenario file and
#			publish in a readable format
# Usage:	perl.exe lr_scenario.pl <scenario_path_and_name>
# Version:	1.0 - February 2011 - Mark Dowd
# Version:	1.1 - 15-Feb 2011 - Mark Dowd
#			Handle illegal XML characters crashing XMLin function
# Version:	1.2 - 16-Feb-2011 - Mark Dowd
#			Uses spaces, rather than tabs, for indents in SharePoint
#			Handle optional run-time settings for groups
# Version:	1.2.1 - 16-Feb-2011 - Mark Dowd
#			Decode monitored machine type
#			Provide summary of Groups in header
#			Sundry fixes relating  to HASH/ARRAY
# Version:	1.2.2 - 23-Feb-2011 - Mark Dowd
#			Fix VUser per Injector count anomaly
#			Fix missing monitors causing abend
# Version:	1.3 - 24-Feb-2011 - Mark Dowd
#			Move monitored machine type to individuals
# Version:	1.4 - 2-Mar-2011
#			Sort groups
#			Handle percentage mode
#			Handle spaces in script names
# Version:	1.4.1 - 3-Mar-2011
#			Fixed single monitor problem
#			Fixed missing group and schedule links
# Version:	1.4.2 - 4-Mar-2011
#			Correctly handle multiple key values
#			Fixed sorting of monitored machine names
# Version:	1.5 - 8-Mar-2010
#			Output to a file
#			If input parameter is a directory, do all in that directory
# Version:	1.5.1 - 5-May-2011
#			Fixes GroupScheduler appearing as HASH/ARRAY
# Version:	1.5.2 - 29-Nov-2011
#			Adds output for script Proxy configuration
#######################################################################
use strict;
use strict "subs";
use feature "switch";
use File::Spec;
use XML::Simple;
#######################################################################
# Global configuration
#######################################################################
my $scriptver = "1.5.2";
my $scriptdate = "29-Nov-2011";
#######################################################################
# Global hashes
#######################################################################
my $scenario;
#######################################################################
# Subroutines
#######################################################################
sub capture_lrs {
	# Load .lrs file
	my $infile = shift;
	open(INFILE, $infile) or die "Cannot open $infile: $!";
	while (<INFILE>) {
		my $line = $_;
		chomp $line;
		if ($line) {
			# Non-blank
			if (/^\{(.+)/) {
				process_lrs(\$scenario->{$1});
			} else {
				# At this level there should be no "stray" lines
				print STDERR "Error: Unhandled line $line\n";
			}
		}
	}
	close INFILE;
}
sub write_value {
	my $ref = shift;
	my $value = shift;
	
	unless ($$ref) {
		$$ref = $value;
	} else {
		my $reftype = ref($ref);
		given ($reftype) {
			when (/ARRAY|REF/) {
				push @$$ref, $value;
			}
			when (/SCALAR|HASH/) {
				# Save current values and undef the reference
				my $temp = $$ref;
				$$ref = undef;
				
				# Write the old value as an array element
				push @$$ref, $temp;
				push @$$ref, $value;
			}
			default {
				my $type = ref($$ref);
				print STDERR "Unexpected ref type $type trying to push $value\n";
			}
		}
	}
}
sub process_lrs {
	my $root = shift;
	my @lines;
	while (<INFILE>) {
		chomp;
		given ($_) {
			when ('') { # Ignore empty lines
				break;
			}
			when (/^\{(.+)/) { # Capture start of subnode
				# Does this node already exist?
				if ($$root->{$1}) {
					# If it's not already an array, make it so
					if (ref($$root->{$1}) eq 'HASH') {
						# Save current values and undef the reference
						my $temp = $$root->{$1};
						$$root->{$1} = undef;
						
						# Write the old value as an array element
						push @{ $$root->{$1} }, $temp;
					}
					# Create the new array element
					my $depth = push @{ $$root->{$1} }, undef;
					
					# Process
					process_lrs(\@{ $$root->{$1} }[$depth - 1]);
				} else {
					process_lrs(\$$root->{$1});
				}
				break;
			}
			when (/^\}/) {
				# Finished: Process @lines
				if (@lines) {
					# Establish main section type
					given ($lines[0]) {
						# INI file
						when (/\[(.+)\]/) {
							my $inisection;
							for (@lines) {
								if (/^\[(.+)\]/) {
									$inisection = $1;
									$$root->{$inisection} = undef;
								} else {
									my ($key, $data) = /\s*(.+?)=(?:\w+V1\|)?(.*)\s*/;
									write_value(\$$root->{$inisection}->{$key}, $data);
								}
							}
							break;
						}
						# XML section
						when (/<\?xml/) {
							# Join up data lines and remove inter-node whitespace
							my $data = join '', @lines;
							$data =~ s/>\s+</></g;
							
							# Remove leading ?xml node and replace £ with # (the £ kills XMLin in UTF-8 mode)
							$data =~ s/<\?xml.+?>(.+)/$1/;
							$data =~ s/£/#/g;
							
							# Convert the XML into a tree-view
							my $xml = XMLin($data);
							$$root = $xml;
							break;
						}
						# key=value pairs
						when (/.+?=.*/) {
							for (@lines) {
								# Capture key=<ignore_type>value
								my ($key, $data) = /\s*(.+?)=(?:\w+V1\|)?(.*)\s*/;
								
								given ($data) {
									# Embedded INI format
									when (/^\[(.+)\].+\\r\\n/) {
										my @inilines = split /\\r\\n/, $data;
										my $inisection;
										for (@inilines) {
											if (/^\[(.+)\]/) {
												$inisection = $1;
												$$root->{$key}->{$inisection} = undef;
											} else {
												my ($inikey, $inidata) = /\s*(.+?)=(.*)\s*/;
												$inidata =~ s/(")?(.+)\1/$2/;
												write_value(\$$root->{$key}->{$inisection}->{$inikey}, $inidata);
											}
										}
										break;
									}
									# Embedded XML format
									when (/^<\?xml/) {
										# Join up data lines and remove inter-node whitespace
										$data =~ s/>\s+</></g;
										
										# Remove leading ?xml node and replace £ with # (the £ kills XMLin in UTF-8 mode)
										$data =~ s/<\?xml.+?>(.+)/$1/;
										$data =~ s/£/#/g;
										
										# Convert the XML into a tree-view
										my $xml = XMLin($data);
										$$root->{$key} = $xml;
										break;
									}
									# Standard data type
									default {
										write_value(\$$root->{$key}, $data);
										break;
									}
								}
							}
							break;
						}
					}
				}
				# Exit level
				last;
			}
			default {
				# If not empty, save the line
				if ($_) {
					push @lines, $_;
				}
			}
		}
	}
	return;
}
sub sec_to_time {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);
	my $ss = sprintf("%02d", $sec);
	my $mm = sprintf("%02d", $min);
	my $hh = sprintf("%02d", $hour);
	return "$hh:$mm:$ss";
}
sub format_time{
	my $intime = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($intime);
	my $yyyy = 1900 + $year;
	my $mmm = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec )[$mon];
	my $dd = sprintf("%02d", $mday);
	my $hh = sprintf("%02d", $hour);
	my $mm = sprintf("%02d", $min);
	my $ss = sprintf("%02d", $sec);

	return "$dd-$mmm-$yyyy $hh:$mm:$ss";

}
sub scheduling {
	my $sched = shift;
#	print OUTPUT "Schedule  $$schedule->{actual}->{Name}, by $$schedule->{actual}->{Manual}->{SchedulerType}, start $$schedule->{StartMode}->{StartModeType}\n";
}
sub generate {
	my $outputname = shift;
	my $inputname = shift;
	open(OUTPUT, "> $outputname") or die "Can't open $outputname: $!";
	
	my $now = format_time(time);

	print OUTPUT "#######################################################################\n";
	print OUTPUT "# Generated on $now\n";
	print OUTPUT "# Using Script: $0\n";
	print OUTPUT "# Version: $scriptver ($scriptdate)\n";
	print OUTPUT "#######################################################################\n";


	
	my ($tests, $schedules);
	
	# Process Tests
	for my $tname (sort keys %{ $scenario->{TestChief} }) {
		my $ref = \$scenario->{TestChief}->{$tname};
		$tests->{$tname}->{test} = $$ref;
	}
		
	# Process groups
	if ($scenario->{GroupChief}) {
		# Identify current schedule
		my $schedule = \$scenario->{ScenarioSchedulerConfig}->{Schedulers};
		# Find current schedule
		if (ref($$schedule->{Scheduler}) eq 'HASH') {
			$$schedule->{actual} = $$schedule->{Scheduler};
		} else {
			for (@{ $$schedule->{Scheduler} }) {
				if ($_->{ID} == $$schedule->{CurrentSchedulerId}) {
					$$schedule->{actual} = $_;
					last;
				}
			}
		}
		
		# Get Schedule
		my $reftype = ref($$schedule->{actual}->{Manual}->{Groups}->{GroupScheduler});
		given ($reftype) {
			when (/ARRAY|REF/) {
				for my $sched (@{ $$schedule->{actual}->{Manual}->{Groups}->{GroupScheduler} }) {
					my $sref = \$sched;
					$schedules->{$$sref->{GroupName}} = $$sref;
				}
			}
			when (/SCALAR|HASH/) {
					my $sref = \$$schedule->{actual}->{Manual}->{Groups}->{GroupScheduler};
					$schedules->{$$sref->{GroupName}} = $$sref;
			}
			default {
				my $type = $reftype;
				print STDERR "Unexpected ref type $type trying to capture GroupScheduler\n";
			}
		}
	
		# Get groups
		for my $gname (keys %{ $scenario->{GroupChief} }) {
			# Add Group to Test
			my $gref = \$scenario->{GroupChief}->{$gname};
			my $tname = $$gref->{ChiefSettings}->{5};
			$tests->{$tname}->{group} = $$gref;
			my $sref = \$schedules->{lc $gname};
			$tests->{$tname}->{sched} = $$sref;
			delete $schedules->{lc $gname};;
		}
	}
	
	# Scenario
	{
		# Print header
		print OUTPUT "Scenario\n========\n";
		
		# Actual file analysed
		my ($path, $name) = File::Spec->rel2abs($inputname) =~ /(.+)\\(.+)\.lrs/;
		print OUTPUT "Name      $name\n";
		print OUTPUT "Path      $path\n";
		print OUTPUT "Version   $scenario->{Product}->{Version}\n";
		
		# Scenario file last used as
		print OUTPUT "Last      $scenario->{ScenarioPrivateConfig}->{Path}\n";
		
		# Scheduling 
		my $schedule = \$scenario->{ScenarioSchedulerConfig}->{Schedulers};
		# Handle Global scheduling
		if ($$schedule->{actual}->{Manual}->{SchedulerType} eq 'Global') {
			my $global = \$$schedule->{actual}->{Manual}->{Global};
			print OUTPUT "Schedule  $$schedule->{actual}->{Name}, by $$schedule->{actual}->{Manual}->{SchedulerType}, start $$schedule->{StartMode}->{StartModeType}\n";
		}
		
		# VUser Count
		if ($scenario->{ScenarioGeneralConfig}->{ScenarioType} == 2) {
			my $vuser;
			if (ref($scenario->{ScenarioPrivateConfig}->{Vusers}) eq 'ARRAY') {
				$vuser = $scenario->{ScenarioPrivateConfig}->{Vusers}[0];
			} else {
				$vuser = $scenario->{ScenarioPrivateConfig}->{Vusers};
			}
			print OUTPUT "Vusers    $vuser (percentage mode)\n";
		}
		
		# Test count
		my ($count, $disabled, $tname, @test);
		for my $key (sort keys %$tests) {
			my $test = \$tests->{$key};
			$count++;
			(undef, $tname) = $$test->{test}->{Path} =~ /(.+)\\.+\\(.+)\.usr/;
			if ($tname =~ /\s/) {
				$key .= ' ***contains spaces***';
				$tname =~ s/\s/\_/g; # Fix blanks in script name
			}
			# Check out the group's status
			if ($scenario->{ScenarioGeneralConfig}->{ScenarioType} == 1) {
				unless ($$test->{group}->{ChiefSettings}->{Enabled}) {
					$disabled++;
					$key .= ' (disabled)';
				}
			}
			push @test, $key;
		}
		print OUTPUT "Tests     $count";
		if ($disabled) {
			print OUTPUT ", $disabled disabled";
		}
		print OUTPUT "\n";
		for (@test) {
			print OUTPUT "          - $_\n";
		}
		print OUTPUT "==========================================================================\n";
	}
	
	# Tests
	{
		for my $key (sort keys %$tests) {
			my $test = \$tests->{$key};
			my ($path, $tname) = $$test->{test}->{Path} =~ /(.+)\\.+\\(.+)\.usr/;
			$tname =~ s/\s/\_/g; # Fix blanks in script name
			
			# Group name
			print OUTPUT "Test      $key";
			if ($key =~ /\s/) {
				print OUTPUT " ***contains spaces***";
			}
			print OUTPUT "\n";
			if ($scenario->{ScenarioGeneralConfig}->{ScenarioType} == 1) {
				unless ($$test->{group}->{ChiefSettings}->{Enabled}) {
					print OUTPUT "          Disabled\n";
				}
			}
			
			# Script name
			print OUTPUT "Script    '$tname' in $path\n";
			my $type;
			if ($$test->{test}->{SubType}) {
				$type = ($$test->{test}->{SubType} =~ /(?:Multi\+)?(.+)/)[0];
			} else {
				if ($$test->{test}->{Type}) {
					$type = $$test->{test}->{Type};
				} else {
					$type = "Unknown";
				}
			}
			
			print OUTPUT "Type      $type\n";
			
			# VUsers on Load Generators
			my $notfirst;
			my $gencount;
			if ($$test->{group}) {
				for my $vu (keys %{ $$test->{group} }) {
					unless ($vu eq 'ChiefSettings') {
						$gencount->{$$test->{group}->{$vu}->{9}}++;
					}
				}
			} else {
				for (@{ $scenario->{ScenarioGroupsData}->{SCHED_GROUP_DATA} }) {
					if ($_->{SCHED_GROUP_NAME} eq $key) {
						$gencount->{$_->{TEST_HOSTS_NAMES}} = "$_->{TEST_PERCENT_DISTRIBUTION}%";
						last;
					}
				}
			}
			print OUTPUT "Vusers    ";
			if ($gencount) {
				for my $generator (keys %{ $gencount }) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "$gencount->{$generator} on $generator\n";
				}
			} else {
				print OUTPUT "\n";
			}
			print OUTPUT "--- Run-Time Settings ---\n";
			# Run logic
			if ($$test->{test}->{ConfigUsp} && $$test->{test}->{ConfigUsp}->{RunLogicRunRoot}) {
				my $root = \$$test->{test}->{ConfigUsp}->{RunLogicRunRoot};
				# Iterations
				if ($$root->{RunLogicNumOfIterations}) {
					print OUTPUT "Iter      $$root->{RunLogicNumOfIterations}\n";
				}
				
				# Pacing
				if ($$root->{RunLogicPaceType}) {
					print OUTPUT "Pacing    ";
					given ($$root->{RunLogicPaceType}) {
						when ('Asap') {
							print OUTPUT "As soon as possible\n";
							break;
						}
						when ('Const') {
							print OUTPUT "At fixed $$root->{RunLogicPaceConstTime} seconds\n";
							break;
						}
						when ('ConstAfter') {
							print OUTPUT "After fixed $$root->{RunLogicPaceConstAfterTime} seconds\n";
							break;
						}
						when ('After') {
							print OUTPUT "After random $$root->{RunLogicAfterPaceMin} to $$root->{RunLogicAfterPaceMax} seconds\n";
							break;
						}
						when ('Random') {
							print OUTPUT "At random $$root->{RunLogicRandomPaceMin} to $$root->{RunLogicRandomPaceMax} seconds\n";
							break;
						}
						default {
							print STDERR "Error: Unexpected run logic '$$root->{RunLogicPaceType}'\n";
							break;
						}
					}
				}
			}
			
			# Logging
			if ($$test->{test}->{Config}) {
				print OUTPUT "Logging   ";
				$notfirst = undef;
				my $root = \$$test->{test}->{Config}->{Log};
				given ($$root->{LogOptions}) {
					when ('LogDisabled') {
						print OUTPUT "Disabled\n";
						$notfirst = 1;
						break;
					}
					when ('LogBrief') {
						print OUTPUT "Standard\n";
						$notfirst = 1;
						break;
					}
					when ('LogExtended') {
						print OUTPUT "Extended\n";
						$notfirst = 1;
						if ($$root->{MsgClassParameters}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
							print OUTPUT "Parameter Substitution\n"
						}
						if ($$root->{MsgClassData}) {
							unless ($notfirst) {
								$notfirst = 1;
							} else {
								print OUTPUT "          ";
							}
							print OUTPUT "Data returned by server\n"
						}
						if ($$root->{MsgClassFull}) {
							unless ($notfirst) {
								$notfirst = 1;
							} else {
								print OUTPUT "          ";
							}
							print OUTPUT "Advanced trace\n"
						}
						break;
					}
					default {
						print STDERR "Error: Unexpected logging level '$$root->{LogOptions}'\n"
					}
				}
				if ($$root->{LogOptions} ne 'LogDisabled' && $$root->{AutoLog}) {
					my $size;
					if ($$root->{AutoLogBufferSize}) {
						$size = $$root->{AutoLogBufferSize};
					} else {
						$size = 1;
					}
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Log on error for $size kb\n"
				}
				# Think time
				print OUTPUT "Think     ";
				$root = \$$test->{test}->{Config}->{ThinkTime};
				given ($$root->{Options}) {
					when ('NOTHINK') {
						print OUTPUT "None";
						break;
					}
					when ('RECORDED') {
						print OUTPUT "As recorded";
						break;
					}
					when ('MULTIPLY') {
						print OUTPUT "Multiply by $$root->{Factor}";
						break;
					}
					when ('RANDOM') {
						print OUTPUT "Random from $$root->{ThinkTimeRandomLow}% to $$root->{ThinkTimeRandomHigh}%";
						break;
					}
					default {
						print STDERR "Error: Unexpected think time model '$$root->{Options}'\n"
					}
				}
				if ($$root->{Options} ne 'NOTHINK' && $$root->{LimitFlag}) {
					print OUTPUT ". Limit to $$root->{Limit} seconds."
				}
				print OUTPUT "\n";
				# Additional Attributes
				if ($$test->{test}->{Config}->{CommandArguments}) {
					print OUTPUT "Add Arg   ";
					
					$notfirst = undef;
					for my $argkey (sort keys %{ $$test->{test}->{Config}->{CommandArguments} }) {
						unless ($argkey =~ /^\~/) {
							unless ($notfirst) {
								$notfirst = 1;
							} else {
								print OUTPUT "          ";
							}
							print OUTPUT "$argkey = $$test->{test}->{Config}->{CommandArguments}->{$argkey}\n";
						}
					}
				}
				# Miscellaneous
				print OUTPUT "Misc      ";
				$root = \$$test->{test}->{Config}->{General};
				$notfirst = undef;
				if ($$root->{ContinueOnError}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Continue on error\n";
				}
				if ($$root->{FailTransOnErrorMsg}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Fail open transaction on lr_error_message\n";
				}
				if ($$test->{test}->{Config}->{WEB}) {
					if ($$test->{test}->{Config}->{WEB}->{SnapshotOnErrorActive}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Generate snapshot on error\n";
					}
				}
				if ($$root->{UseThreads}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Run as thread\n";
				} else {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Run as process\n";
				}
				if ($$root->{AutomaticTransactions}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Define each action is a transaction\n";
				}
				if ($$root->{AutomaticTransactionsPerFunc}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					print OUTPUT "Define each step is a transaction\n";
				}
				# Modem
				print OUTPUT "Modem     ";
				$root = \$$test->{test}->{Config}->{ModemSpeed};
				unless ($$root->{EnableModemSpeed}) {
					print OUTPUT "Use maximum bandwidth\n"
				} else {
					if ($$root->{EnableCustomModemSpeed}) {
						print OUTPUT "Speed limited to $$root->{CustomModemSpeed} (custom)\n"
					} else {
						print OUTPUT "Speed limited to $$root->{ModemSpeed}\n"
					}
				}
				# Browser
				if ($$test->{test}->{Config}->{WEB}->{BrowserType}) {
					print OUTPUT "Browser   ";
					$root = \$$test->{test}->{Config}->{WEB};
					$notfirst = undef;
					if ($$root->{CustomUserAgent}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "User-agent ($$root->{CustomUserAgent}\n";
					}
					if ($$root->{SimulateCache}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Simulate browser cache";
						if ($$root->{KeepNonTextMimeType} && !$$root->{IgnoreContentCachingTypes}) {
							unless ($notfirst) {
								$notfirst = 1;
							} else {
								print OUTPUT "          ";
							}
							print OUTPUT " ignoring $$root->{KeepNonTextMimeType}";
						}
						if ($$root->{CacheAlwaysCheckForNewerPages} eq 'Yes') {
							print OUTPUT ", always checking for newer pages";
						}
						print OUTPUT "\n";
					}
					if ($$root->{SearchForImages} && $$root->{SearchForImages} eq 'True') {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Download non-HTML resources\n";
					}
				}
				# Proxy
				if ($$test->{test}->{Config}->{WEB}->{ProxyUseProxy} || $$test->{test}->{Config}->{WEB}->{ProxyUseBrowser}) {
					print OUTPUT "Proxy     ";
					$root = \$$test->{test}->{Config}->{WEB};
					$notfirst = undef;
					if ($$root->{ProxyUseBrowser}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Use browser settings\n";
					}
					if ($$root->{ProxyAutoConfigScriptURL}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Auto ($$root->{ProxyAutoConfigScriptURL})\n";
					}
					if ($$root->{ProxyUseProxyServer}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "HTTP $$root->{ProxyHTTPHost}:$$root->{ProxyHTTPPort}\n";
						if (!$$root->{ProxyUseSame}) {
							print OUTPUT "          ";
							print OUTPUT "HTTPS $$root->{ProxyHTTPSHost}:$$root->{ProxyHTTPSPort}\n";
						}
					}
					if ($$root->{ProxyUserName}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "User ($$root->{ProxyUserName})\n";
					}
					if ($$root->{ProxyBypass}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Bypass ($$root->{ProxyBypass})\n";
					}
					if ($$root->{ProxyNoLocal}) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						print OUTPUT "Bypass local\n";
					}
				}
			}
			# Schedule
			if ($$test->{sched}) {
				my $root = \$$test->{sched};
				print OUTPUT "--- Scheduling ----------\n";
				print OUTPUT "Sched     ";
				$notfirst = undef;
				if ($$root->{StartupMode}) {
					for my $mode (keys %{ $$root->{StartupMode} }) {
						unless ($notfirst) {
							$notfirst = 1;
						} else {
							print OUTPUT "          ";
						}
						given ($mode) {
							when ('StartAfterGroup') {
								print OUTPUT "Start after group '$$root->{StartupMode}->{$mode}'\n";
							}
							when ('StartIntervalAfterScenarioBeginning') {
								my $delay = sec_to_time($$root->{StartupMode}->{$mode});
								print OUTPUT "Start $delay after scenario start\n";
							}
							when ('StartAtScenarioBegining') {
								print OUTPUT "Start at scenario beginning\n";
							}
							default {
								print STDERR "Error: Unexpected StartupMode '$mode = $$root->{StartupMode}->{$mode}'\n";
							}
						}
					}
				}
				my $phases = $$root->{Scheduling}->{DynamicScheduling};
				if ($phases->{RampUp}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					my $every = sec_to_time($phases->{RampUp}->{Batch}->{Interval});
					print OUTPUT "Start $phases->{RampUp}->{TotalVusersNumber} vusers, $phases->{RampUp}->{Batch}->{Count} every $every\n";
					delete $phases->{RampUp};
				}
				if ($phases->{Duration}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					my $runfor = sec_to_time($phases->{Duration}->{RunFor});
					print OUTPUT "Run for $runfor\n";
					delete $phases->{Duration};
				}
				if ($phases->{StopAll}) {
					delete $phases->{StopAll};
				}
				if ($phases->{Run}) {
					delete $phases->{Run};
				}
				if ($phases->{RampDownAll}) {
					unless ($notfirst) {
						$notfirst = 1;
					} else {
						print OUTPUT "          ";
					}
					my $every = sec_to_time($phases->{RampDownAll}->{Batch}->{Interval});
					print OUTPUT "Stop $phases->{RampDownAll}->{Batch}->{Count} every $every\n";
					delete $phases->{RampDownAll};
				}
				for my $key (keys %$phases) {
					print STDERR "Error: Found unexpected schedule phase '$key'\n";
				}
			}
			print OUTPUT "==========================================================================\n";
		}
	
	}
	
	# Monitors
	{
		print OUTPUT "Monitors\n";
		if ($scenario->{LRExtensions}->{lr_monitors}->{ResourceMonitoring}->{ResourceMonitoringMachines}->{ResourceMonitoredMachine}) {
			my $types;
			if (ref($scenario->{LRExtensions}->{lr_monitors}->{ResourceMonitoring}->{ResourceMonitoringMachines}->{ResourceMonitoredMachine}) eq 'HASH') {
				my $m = \$scenario->{LRExtensions}->{lr_monitors}->{ResourceMonitoring}->{ResourceMonitoringMachines}->{ResourceMonitoredMachine};
				print OUTPUT "-------------------------\n$$m->{MonitoredMachineName}\n";
				# Individual monitors
				for (sort @{ $$m->{ItemList}->{MonItemPlus} }) {
					push @{ $types->{$_->{MonItem}->{DisplayerName}} }, $_->{MonItem}->{Name};
				}
				
				# Print monitor details by type
				for my $type (sort keys %$types) {
					print OUTPUT "  Type -> $type\n";
					for (sort @{ $types->{$type} }) {
						print OUTPUT "          $_\n";
					}
				}
				
				# Clean up
				$types = undef;
			} else {
				for (sort {$a->{MonitoredMachineName} cmp $b->{MonitoredMachineName}} @{ $scenario->{LRExtensions}->{lr_monitors}->{ResourceMonitoring}->{ResourceMonitoringMachines}->{ResourceMonitoredMachine} }) {
					print OUTPUT "-------------------------\n$_->{MonitoredMachineName}\n";
					# Individual monitors
					if ($_->{ItemList}->{MonItemPlus}) {
						if (ref($_->{ItemList}->{MonItemPlus}) eq 'ARRAY') {
							for (sort @{ $_->{ItemList}->{MonItemPlus} }) {
								push @{ $types->{$_->{MonItem}->{DisplayerName}} }, $_->{MonItem}->{Name};
							}
						} else {
							push @{ $types->{$_->{ItemList}->{MonItemPlus}->{MonItem}->{DisplayerName}} }, $_->{ItemList}->{MonItemPlus}->{MonItem}->{Name};
						}
						
						# Print monitor details by type
						for my $type (sort keys %$types) {
							print OUTPUT "  Type -> $type\n";
							for (sort @{ $types->{$type} }) {
								print OUTPUT "          $_\n";
							}
						}
						
						# Clean up
						$types = undef;
					}
				}
			}
		}
	}
	print OUTPUT "==========================================================================\n";

}
#######################################################################
# Mainline code
#######################################################################
unless ($ARGV) {
	print "Usage: [perl] lr_scenario.pl {file|dir} [...]\n";
	print "\tfile\tLoadRunner scenario file\n";
	print "\tdir\tSingle-depth directory containing scenario files\n";
}
for (@ARGV) {
	my $line = $_;
	# If this is a directory
	if (-d $line) {
		# Append missing suffix
		$line =~ s/(.+)\\?/$1\\/;
		
		# For each .lrs found
		my @scenarios = glob("$line*.lrs");
		
		for (@scenarios) {
			my $infile = $_;
			my ($outfile) = $infile =~ /(.+\.)lrs/;
			$outfile .= 'txt';
			
			print "Processing $infile\n";
			
			capture_lrs($infile);
			generate($outfile, $infile);
			$scenario = {};
		}
	} else {
		# If this is a .lrs file
		if (-f $line && $line =~ /\.lrs$/) {
			my $infile = $line;
			my ($outfile) = $infile =~ /(.+\.)lrs/;
			$outfile .= 'txt';
			
			print "Processing $infile\n";
			
			capture_lrs($infile);
			generate($outfile, $infile);
			$scenario = {};
		}
	}
}
