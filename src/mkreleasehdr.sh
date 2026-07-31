#!/bin/sh

if [ -n "${KEYDB_BUILD_GIT_SHA1:-}" ]; then
  if ! printf '%s\n' "$KEYDB_BUILD_GIT_SHA1" | grep -Eq '^[0-9a-fA-F]{40}$'; then
    echo "KEYDB_BUILD_GIT_SHA1 must be a full 40-character Git SHA" >&2
    exit 1
  fi
  GIT_SHA1=$(printf '%s' "$KEYDB_BUILD_GIT_SHA1" | cut -c1-8)
else
  GIT_SHA1=`(git show-ref --head --hash=8 2> /dev/null || echo 00000000) | head -n1`
fi

if [ -n "${KEYDB_BUILD_GIT_DIRTY:-}" ]; then
  case "$KEYDB_BUILD_GIT_DIRTY" in
    0|1) GIT_DIRTY=$KEYDB_BUILD_GIT_DIRTY ;;
    *)
      echo "KEYDB_BUILD_GIT_DIRTY must be 0 or 1" >&2
      exit 1
      ;;
  esac
else
  GIT_DIRTY=`git diff --no-ext-diff 2> /dev/null | wc -l`
fi
BUILD_ID=`uname -n`"-"`date +%s`
if [ -n "$SOURCE_DATE_EPOCH" ]; then
  BUILD_ID=$(date -u -d "@$SOURCE_DATE_EPOCH" +%s 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" +%s 2>/dev/null || date -u +%s)
fi
test -f release.h || touch release.h
(cat release.h | grep SHA1 | grep $GIT_SHA1) && \
(cat release.h | grep DIRTY | grep $GIT_DIRTY) && exit 0 # Already up-to-date
echo "#define REDIS_GIT_SHA1 \"$GIT_SHA1\"" > release.h
echo "#define REDIS_GIT_DIRTY \"$GIT_DIRTY\"" >> release.h
echo "#define REDIS_BUILD_ID \"$BUILD_ID\"" >> release.h
touch release.c # Force recompile of release.c
