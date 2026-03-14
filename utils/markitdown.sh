#!/bin/bash

echo '#### Installing markitdown'
echo '#################################################################'
git clone git@github.com:microsoft/markitdown.git
cd markitdown
pip install -e 'packages/markitdown[all]'

echo '#### Python3 installed'
echo '#### Usage
  Command-Line
  markitdown path-to-file.pdf > document.md
  Or use -o to specify the output file:
  markitdown path-to-file.pdf -o document.md'
echo '#################################################################'
