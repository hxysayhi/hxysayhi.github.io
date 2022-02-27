#! /usr/bin/env bash

git checkout gh
git merge master --no-edit
ret=$?
if [[ "${ret}" != "0" ]]; then
    echo auto merge failed!
    exit ${ret}
fi

git push github gh:main
git checkout master

echo done!
