(*
	MP3 CD Maker
	
	So iTunes already does this.
	But, as you probably noticed, you have to convert all your songs to MP3.
	Okay, that gets tedious, especially since a CD will hold 100 MP3s... 
	And after burning, I've got MP3 versions of my songs floating around my library.
	
	Solution 1: ditch iTunes for a good music library.
	Solution 2: this script.
	
	This script will:
	1. Step through any playlist, to include a Genius mix, or DJ shuffle.
	2. Skip over songs that are already MP3s.
	3. Clean up after itself as it goes.
	4. Automatically bail if there are 10 failures in a row. 
	5. Write a log to the desktop.
	6. Do a Pretty Good Job of figuring out what will fit on a CD.
		(Sorry, it doesn't attempt to calculate file system overhead.)
	7. Number as it goes.
	
	You need to:
	1. Set up a playlist.
	2. Start iTunes playing as though you were listening to the playlist.
	3. Hit pause.
	4. Run the script.
	5. It will prompt for a folder. Select an existing folder, or create a new one.
	6. Get a blank CD, and burn the contents of the folder.
	7. You're done!
*)

-- You shouldn't change this unless you're using something
-- other than a CD or DVD. If you're writing to a disk,
-- it'd probably be 4096. 
property sector_size : 2048 -- bytes per sector of a data CD or DVD

-- You can always set this to 0, and just drop a file or two.
property reserve_sectors : 2560 -- reserve this much space for filesystem and such

-- I looked these numbers up on Wikipedia. No idea how accurate they are,
-- but they pass the smell test. 700 MB is the most common CD size I've seen.

-- Just uncomment the capacity you'd like to use.

--property tgt_capacity: 333000 -- a 650 MB CD
property tgt_capacity : 360000 -- a 700 MB CD
--property tgt_capacity: 405000 -- a 800 MB CD
--property tgt_capacity: 445500 -- a 900 MB CD
--property tgt_capacity: 2298496 -- a DVD-R single layer
--property tgt_capacity: 2295104 -- a DVD+R single layer
--property tgt_capacity: 4171712 -- a DVD-R double layer
--property tgt_capacity: 4173824 -- a DVD+R double layer

-- Not commenting as much since the logging does that for us.
on run
	-- Set up logging
	set log_fh to my log_start((path to library folder from user domain as string) & "Logs:MP3 CD Maker.txt")
	my log_mesg(log_fh, "Conversion run begins.")
	my choose_playlist(log_fh)
	
	tell application "iTunes"
		set my_dir to (choose folder with prompt "Pick a target folder")
		my log_mesg(log_fh, "Writing to target folder '" & (my_dir as string)) & "'"
		my log_mesg(log_fh, "Target sector size is " & sector_size & " bytes.")
		my log_mesg(log_fh, "Target capacity is " & tgt_capacity & " sectors.")
		my log_mesg(log_fh, "Target reserved is " & reserve_sectors & " sectors.")
		set sectors_used to (my calc_sectors_used_dir(my_dir))
		my log_mesg(log_fh, "Existing files use " & sectors_used & " sectors.")
		set track_counter to (my calc_track_num(my_dir)) + 1
		set sectors_remaining to tgt_capacity - reserve_sectors - sectors_used
		set conversion_errors to 0
		repeat while sectors_remaining > 0
			my log_mesg(log_fh, "Start track #" & track_counter)
			my log_mesg(log_fh, "Remaining sectors: " & sectors_remaining)
			my log_mesg(log_fh, "Conversion error count: " & conversion_errors)
			if conversion_errors > 9 then
				display alert "Bailing after 10 conversion failures in a row."
				my log_mesg(log_fh, "Bailing from high conversion error count.")
				exit repeat
			end if
			
			try
				set my_track to the current track
				my log_mesg(log_fh, "Working on track " & location of my_track)
				if kind of my_track is "MPEG audio file" then
					-- all we need to do is copy
					my log_mesg(log_fh, "Track is already MP3.")
					set track_file to location of my_track
					my log_mesg(log_fh, "Copying to target dir.")
					tell application "Finder" to set after_op to ((duplicate track_file to my_dir) as alias)
				else
					my log_mesg(log_fh, "Attempting to convert " & kind of my_track & " to MP3.")
					set converted_tracks to (convert my_track)
					if (count converted_tracks) is not 1 then
						error "Conversion returned no files. Is track protected?"
					end if
					set converted_track to first item of converted_tracks
					set conv_file to location of converted_track
					my log_mesg(log_fh, "Converted to: " & (conv_file as string))
					tell application "Finder" to set after_op to ((move conv_file to my_dir) as alias)
					my log_mesg(log_fh, "Moved to: " & (after_op as string))
					my log_mesg(log_fh, "Deleting iTunes entry.")
					-- Notably, this only deletes the entry.
					-- It will fail if the file is still present, but succeed even if the file was merely moved out of the iTunes folder.
					delete converted_track
				end if
				
				-- Work out how much space this is using
				set file_sectors to (my calc_sectors_used_file(after_op))
				my log_mesg(log_fh, "File is " & (file_sectors as string) & " sectors.")
				set sectors_remaining to sectors_remaining - file_sectors
				
				-- Rename the track nicely
				set new_name to (my format_track_name(track_counter, my_track))
				my log_mesg(log_fh, "Renaming track to '" & new_name & "'.")
				tell application "Finder"
					set file_ext to name extension of after_op
					set name of after_op to new_name & "." & file_ext
				end tell
				set track_counter to track_counter + 1
				
				-- only count failures in a row
				my log_mesg(log_fh, "Operation successful.")
				set conversion_errors to 0
			on error e
				my log_mesg(log_fh, "Error: " & (e as string))
				set conversion_errors to conversion_errors + 1
			end try
			try
				my log_mesg(log_fh, "Attempting to move to next track")
				next track
			on error e
				my log_mesg(log_fh, "Error: " & (e as string))
				display alert "Could not get next track, probably at end of playlist, bailing."
				exit repeat
			end try
		end repeat
	end tell
	my log_mesg(log_fh, "Rezeroize track names.")
	my rezeroize_tracks(my_dir, track_counter)
	my log_mesg(log_fh, "Conversion run terminated successfully.")
end run

-- You might want to customize this
-- Track is a track object
-- The caller handles the file extension, ignore that.
on format_track_name(num, the_track)
	tell application "iTunes"
		set the_track_name to name of the_track
	end tell
	return (num as string) & ". " & (the_track_name as string)
end format_track_name

-- Most CD players sort 3 after 20. So we pad with zeroes.
-- This is ugly, but should be pretty reliable.
on rezeroize_tracks(target_dir, track_count)
	set target_path to quoted form of POSIX path of target_dir
	if track_count > 9999 then
		error "Ai Carumba, that's a lot of tracks!"
	else if track_count > 999 then
		do shell script "cd " & target_path & ";" & �
			"for i in [0-9][^0-9]*;" & �
			"do [ \"${i:0:1}\" != \"[\" ] && mv \"$i\" 000\"$i\";" & �
			"done;" & �
			"for i in [0-9][0-9][^0-9]*;" & �
			"do [ \"${i:0:1}\" != \"[\" ] && mv \"$i\" 00\"$i\";" & �
			"done;" & �
			"for i in [0-9][0-9][0-9][^0-9]*;" & �
			"do [ \"${i:0:1}\" != \"[\" ] && mv \"$i\" 0\"$i\";" & �
			"done; exit 0"
	else if track_count > 99 then
		do shell script "cd " & target_path & ";" & �
			"for i in [0-9][^0-9]*;" & �
			"do [ \"${i:0:1}\" != \"[\" ] && mv \"$i\" 00\"$i\";" & �
			"done;" & �
			"for i in [0-9][0-9][^0-9]*;" & �
			"do [ \"${i:0:1}\" != \"[\" ] && mv \"$i\" 0\"$i\";" & �
			"done; exit 0"
	else if track_count > 9 then
		do shell script "cd " & target_path & ";" & �
			"for i in [0-9][^0-9]*;" & �
			"do [ \"${i:0:1}\" != \"[\" ] && mv \"$i\" 0\"$i\";" & �
			"done; exit 0"
	end if
end rezeroize_tracks

-- Calculate the sectors used by all files in a directory.
on calc_sectors_used_dir(target_dir)
	tell application "Finder"
		set the_sizes to size of entire contents of target_dir
	end tell
	set the_sum to 0
	repeat with a_size in the_sizes
		set the_sectors to (a_size / 2048) as double integer
		-- Strangely enough, simple inequality doesn't work even if you take care
		-- to cast both sides.
		if (the_sectors * 2048) < a_size then
			set the_sectors to the_sectors + 1
		end if
		set the_sum to the_sum + the_sectors
	end repeat
	return the_sum
end calc_sectors_used_dir

-- Only change is to the 'cut' command, use field 1 instead of 2.
-- That's because there's no "total" line for a single file
on calc_sectors_used_file(target_file)
	tell application "Finder"
		set the_size to size of target_file
	end tell
	set the_sectors to (the_size / 2048) as double integer
	if (the_sectors * 2048) < the_size then
		set the_sectors to the_sectors + 1
	end if
	return the_sectors
end calc_sectors_used_file

-- Figure out the current track number.
-- Output is either the number or a blank string
on calc_track_num(target_dir)
	set target_path to quoted form of (POSIX path of target_dir)
	do shell script "/bin/ls " & target_path & �
		" | tr -c '[0-9]\\n' '\\t'" & �
		" | cut -f 1" & �
		" | sort -nr" & �
		" | head -n 1"
	-- tr replaces one set of characters with another
	-- the -c complements the first set, so everything that isn't a number or newline becomes a tab
	-- cut is extracting certain fields, by default splitting on tabs.
	-- Now we've just got a list of numbers. sort -nr will do reverse numeric sort
	-- head -n 1 grabs the first line, which is the maximum.	
end calc_track_num

-- Convenience method to pick a playlist, and gives an unsuspecting
-- double-clicker a chance to back out.
on choose_playlist(log_fh)
	tell application "iTunes"
		if player state is in {playing, fast forwarding, rewinding} then
			pause
		end if
		set blurb to "Choose a playlist to convert to a folder of MP3s."
		if player state is paused then
			set current_name to {"Current player state"}
			set blurb to blurb & (ASCII character 13) & "The default is to continue conversion at the current track."
		else
			set current_name to {}
		end if
		set choice_names to (current_name & (name of playlists))
		set choices to (choose from list choice_names �
			with title "Choose Playlist" with prompt blurb �
			OK button name "Convert" default items ((first item of choice_names) as list) �
			without multiple selections allowed and empty selection allowed)
		if (count choices) is 0 then
			error "User cancelled operation."
		end if
		set choice to first item of choices
		if choice is "Current player state" then
			my log_mesg(log_fh, "User selected currently playing playlist, doing nothing.")
		else
			my log_mesg(log_fh, "User selected playlist '" & choice & "'.")
			set the_playlist to (playlist named choice)
			play the_playlist
			pause
			reveal the_playlist
		end if
	end tell
end choose_playlist

-- Simple logging facility
on log_mesg(fh, the_mesg)
	-- Call the date function to format its output
	-- The first part formats the date and time, and then we tack on our
	-- message to the formatting.
	do shell script "echo `date '+%F %T '` " & (quoted form of the_mesg) & " >> " & (quoted form of fh)
end log_mesg

-- So, I figured that if I'm calling a subshell to figure out the date
-- why bother opening a file for access at all?
on log_start(the_log_file)
	tell application "Finder"
		open the_log_file using (path to application "Console")
	end tell
	return POSIX path of the_log_file
end log_start

-- Just note the fact that the log closed properly in case I decide to
-- use AppleScript file handling in the future.
on log_end(fh)
	my log_mesg(fh, "Log closed correctly.")
	do shell script "echo >> " & (quoted form of fh)
end log_end