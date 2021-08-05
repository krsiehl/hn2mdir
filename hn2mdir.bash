#!/bin/bash
shopt -s lastpipe
declare -A MIDS

output-mail()
{
	ID="$1"
	PARENT_ID="$2"
	TIMESTAMP="$3"
	AUTHOR="$4"
	SUBJECT="$5"
	CONTENTS="$6"
	URL="$7"

	printf 'MIME-VERSION: 1.0\n'
	printf 'Message-ID: <%s@news.ycombinator.com>\n' "$ID"
	if [ "$PARENT_ID" = "null" ]; then
		printf 'Subject: %s\n' "$SUBJECT"
	else
		printf 'Subject: Re: %s\n' "$SUBJECT"
		printf 'In-Reply-To: <%s@news.ycombinator.com>\n' "$PARENT_ID"
	fi
	printf 'Date: %s\n' "$(date -R -d "@$TIMESTAMP")"
	printf 'From: %s@news.ycombinator.com\n' "$AUTHOR"
	printf 'To: %s\n' "Kyle Siehl <krsiehl@gmail.com>"
	printf 'Content-Type: text/html; charset=UTF-8\n'
	printf '\n'
	if [ "$PARENT_ID" == "null" ] && [ "$URL" != "null" ]; then
		# TODO: htmlspecialchars($URL) in bash
		printf '<p><a href="%s">%s</a></p>' "$URL" "$URL"
	fi

	if [ "$CONTENTS" != "null" ]; then
		printf '%s' "$CONTENTS"
	fi
}

dump-story()
{
	OUTPUTDIR="$1"
	STORYID="$2"

	STORY="$(curl "https://hn.algolia.com/api/v1/items/${STORYID}")"

	SUBJECT="$(<<<"$STORY" jq -r .title)"
	URL="$(<<<"$STORY" jq -r .url)"
	INDEX=0

	# Flattening code ripped off from: https://til.simonwillison.net/jq/extracting-objects-recursively
	<<<"$STORY" sed -e 's/\\n/ /g' | jq -r \ '[recurse(.children[]) | del(.children)] | .[] | "\(.id) \(.parent_id) \(.created_at_i) \(.author) \(.text)"' \
		| while read ID PARENT_ID TIMESTAMP AUTHOR TEXT; do
			if [ "${MIDS["$ID"]}" = "1" ]; then
				continue
			fi
			FILENAME="$(date +%s).$$_$((INDEX++))"
			output-mail "$ID" "$PARENT_ID" "$TIMESTAMP" "$AUTHOR" "$SUBJECT" "$TEXT" "$URL" > "${OUTPUTDIR}/tmp/${FILENAME}"
			mv "${OUTPUTDIR}/tmp/${FILENAME}" "${OUTPUTDIR}/new/${FILENAME}"
		:
	done
}

case "$#" in
	1) ;;
	*) echo "Usage: $0 output-dir" 1>&2; exit 1;;
esac

OUTPUTDIR="$1"

if [ ! -d "$OUTPUTDIR" ] || [ ! -d "${OUTPUTDIR}/cur" ] || [ ! -d "${OUTPUTDIR}/new" ] || [ ! -d "${OUTPUTDIR}/tmp" ]; then
	echo "$OUTPUTDIR doesn't look like a maildir; bailing"
	exit 1
fi

grep -arh -m1 '^Message-ID' "${OUTPUTDIR}" | grep -oE '[0-9]+' | while read ID; do
	MIDS["$ID"]=1
done

curl "https://hn.algolia.com/api/v1/search?tags=front_page" | jq -r '.hits | .[] | .objectID' | while read STORYID; do
	dump-story "$OUTPUTDIR" "$STORYID"
done
