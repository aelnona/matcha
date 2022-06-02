#!/bin/sh
 
# USAGE:
# matcha [-f [file]] [-t [directory]] [-s [section]] [-p [page]] [-r] [-l]
#
# -f [file]             : open file [file]
# -t [directory]        : use directory as $tmpdir
# -s [section]          : go to section [section]
# -p [page]             : go to page [page] in section
# -r                    : force reloading/unpacking of file
# -l                    : use light theme


# matcha: a simple (?) epub reader

# Depends on links, python3, imagemagick, unzip
# Requires a terminal with support for sixels (e.g. Xterm -ti vt340)

# If your file contains MATCHAIMAGESTART and MATCHAIMAGEEND, then this mightn't work properly, why would you even have those in there in the first place? Might add some safety net in the future, but I can't see any real need for it, so probably not. 


# TODO: 
# - syncing over network
# - images improvements
# - mobile device implementation
# - bookmarking
# - superscripts are currently not displayed correctly
# - support for other different layouts of epub files : pretty much done, but I've only tested on two different books so
# - could use some functions instead of being a single giant mess


# HELP ME
print_help() {
    echo -e "\nUSAGE: \nmatcha -f [file]\n"
    echo "  -f [file]       : open file [file]"
    echo "  -t [directory]  : use [directory] as directory for epub to be unpacked to"
    echo "  -s [section]    : go to section [section]"
    echo "  -p [page]       : go to page [page] in section"
    echo "  -r              : force reloading/unpacking of file"
    echo "  -l              : use light theme"
    echo "  -h              : display this help message"
    echo ""
}

section=1
page=1
overridesection=1
overridepage=1

# Handle flag options 
while getopts "f:t:s:p:rlh" flag ; do
    case "${flag}" in
	# Set file to use (required "option")
	f ) src="${OPTARG}" ; tmpdir="/tmp/matcha-$(basename "$(echo "$src" | sed s/[[:space:]]//g)")/" ; echo "src: $src" ;;
	# Set tmpdir (optional)
	t ) tmpdir="${OPTARG}" ; echo "tmpdir: $tmpdir" ;;
	# Set light theme (optional)
	l ) col="\e[1;47m\e[1;30m" ; echo -e "\n$col\n" ;;
	# Set section (optional)
	s ) overridesection="${OPTARG}" ;;
	# Set page (optional)
	p ) overridepage="${OPTARG}" ;;
	# Force unpack (optional)
	r ) unzip "$src" -d "$tmpdir" -o || exit 1 ;;
	# Print help (optional)
	h ) print_help ; exit 1 ;;
	\?) print_help ; exit 1 ;;
	# Error message
	: ) echo "Option -"$OPTARG" requires an argument." >&2
            exit 1;;
    esac
done

# Quit if no input file is provided
if [ "$src" == "" ] ; then
    print_help
    exit 1
fi

# Number of lines to print before user needs to press enter again. Could definitely be written better but this works.
pagelength=$(( $( resize | tr -d '\n' | sed 's/.*LINES=//g' | sed 's/;.*;//g' ) - 2 ))

imgscale=2 # As a reciprocal of the scale factor.
# Gets screen height and divides by imagescale to get height at which images will be displayed
imgheight=$(( $( xdpyinfo | grep "dimensions" | sed 's/[[:blank:]]*dimensions:[[:blank:]]*[[:digit:]]*x//g ; s/[[:blank:]]*pixels.*//g' | tr -d ' ' ) / $imgscale ))

# Printed before each line of text
margin="        " # YEHA

# Used to store temporary inputs. Probably better ways of doing this
tmpfile="matchacurrent.html"
tmpfile1="matchacurrentformatted.html"

# Check if file exists
if [ -f "$src" ] ; then

    # Get absolute paths because... probably better? 
    src=$( realpath "$src" )
    tmpdir=$( realpath "$tmpdir" )

    # Only unpack file if directory does not already exist
    [ -d "$tmpdir" ] || unzip "${src}" -d "$tmpdir" -o || exit 1
    cd $tmpdir

    # Get file contents in opf file
    contents="$(grep -hwiE "item.*\.x?html" $(realpath $(find | grep ".opf")))"
    
    # Go to parent folder of contents, as hrefs in contents.opf are pretty much always relative to itself
    tmpdir="$(realpath $(dirname -z $( find | grep ".opf" )))"
    cd $tmpdir
    
    # For each html file in contents
    echo "$contents" | while read -r file ; do
	# Skip to section if user has overridden
	if [ "$overridesection" -gt "$section" ] ; then section=$(($section + 1)) ; continue; fi
	
	! [ -f "$tmpfile" ] || rm $tmpdir/$tmpfile
	! [ -f "$tmpfile1" ] || rm $tmpdir/$tmpfile1

	# Convert contents to filepaths
	file=$( realpath "$tmpdir/$(echo "$file" | sed 's/.*href[[:blank:]]*=[[:blank:]]*\"//g ; s/html[[:blank:]]*\".*/html/g' | tr -d ' ' )" )
	# [ -f "$file" ] || continue
	echo -e "Opening $file\n\n" 
	
	# Replace image hyperlinks with tags such that they can be found later
	sed 's/.*<[[:blank:]]*img.*src="\([^"]*\)".*/MATCHAIMAGESTART\1MATCHAIMAGEEND/g' "$file" > "$tmpdir/$tmpfile"
	sed -i 's/.*<[[:blank:]]*image.*href="\([^"]*\)".*/MATCHAIMAGESTART\1MATCHAIMAGEEND/g' "$tmpdir/$tmpfile"
	
	# Convert to readable format via links
	links -dump "$tmpdir/$tmpfile" > "$tmpdir/$tmpfile1"

	# Go through line by line
	n=1
	while read -r line ; do

	    # Skip to page if user has overridden. Seems inefficient
	    if [ "$overridepage" -gt "$page" ] ; then
		n=$(( $n + 1 ))
		if [ $(($n % $pagelength)) == 0 ] ; then page=$(($page + 1)) ; fi
		continue
	    fi
	    
	    # Check if image. Probably stupidly inefficient
	    if [[ "$line" =~ "^.*MATCHAIMAGESTART.*MATCHAIMAGEEND$" ]] ; then

		# Store contents of line in variable and remove tags. Should leave you with the file path

		# Go to folder containing html file
		cd $(dirname "$file")

		# Get path to image (only necessary if html files are in separate directories to image files)
		img="$( realpath "$(echo "$line" | sed 's/MATCHAIMAGESTART//g ; s/MATCHAIMAGEEND//g ; s/%20/ /g' )" )"

		# Un-URLise ; decode percent encoding using some python
		# TODO: replace with some function to remove Python dependency
		img="$( python3 -c "import sys, urllib.parse as ul; \
		      	         print(ul.unquote_plus(sys.argv[1]))" "$img" )"
		
		# Display image
		convert "$img" -geometry x${imgheight} sixel:-

		# n is used to keep track of how many lines there are left to print before we need to
		# wait for user input to go to next page, and images will take up a lot of space
		n=$(( n + (( $pagelength + 4 )/ $imgscale) )) 
	    else
		# If not image, print line 
		echo "$margin$line"
		# Increment line counter
		n=$(( n + 1 ))
	    fi
	    # If at pagelength, user needs to press enter to continue (or q to quit)
	    if [ $(($n % $pagelength)) == 0 ] ; then
		# Display position in book
		echo -n "s${section}p${page} "
		# Get user input
		read -p ":" qu < /dev/tty
		echo
		page=$(( $page + 1 ))
		if [[ "$qu" == "q" || "$qu" == "Q" ]] ; then echo -e "\e[1;0m]" ; exit 0 ; fi
	    fi
	done < "$tmpdir/$tmpfile1"
	
	# links -g -html-bare-image-autoscale 1 -html-image-scale 50 -html-g-background-color 0xFFFFFF -menu-background-color 0x000000 -menu-foreground-color 0x454545 $file

	# Used to prevent continuous stream of stuff
	# Display position in book
	echo -n "s${section}p${page} "
	# Get user input
	read -p ": " qu < /dev/tty
	echo
	section=$(( $section + 1 ))
	page=1

	if [[ "$qu" == "q" || "qu" == "Q" ]] ; then echo -e "\e[1;0m" ; exit 0 ; fi
    done
else
    # File not found error
    echo "File \"$src\" not found. Exiting...">&2
	echo -e "\e[1;0m"
    exit 1

fi

# Clear colours in case of light theme. Won't run if you ctrl-c it or it just dies for some reason,
# so make sure you press q ( or don't, it's not that hard to fix )
echo -e "\e[1;0m"

