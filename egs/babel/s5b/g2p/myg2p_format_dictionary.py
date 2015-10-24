#!/usr/bin/env python
# $Id: lex2news.py 336 2013-01-18 18:22:37Z arlo $
DESCRIPTION="""
This converts from a lexicon format to the 'news' format used by
m2maligner.  This borrows heavily from the hescii script, and is
used by the Swordfish team fo the Babel Project.

Encoding: UTF8 -> hescii
 A UTF8 byte string is encoded to hescii as follows:
  1. A Unicode character string is decoded from a UTF-8 byte string
  2. Non-ASCII whitespace (> \u007F) maps to plain space (\u0020)
  3. Split into substrings delimited by whitespace separators
  4. Non-whitespace substrings are mapped as follows:
    - First encode Unicode characters -> UTF8 bytes
    - Then encode UTF8 bytes -> hexadecimal (ASCII) characters
    - Optionally prepend a prefix character (default: 'x')
  5. Join the substrings, retaining whitespace separators

Decoding: hescii -> byte string
 A hescii string (ASCII-encoded text) is decoded to UTF8 as follows:
  1. Search left-to-right for prefix followed by pairs of hexadecimals
  2. For each match, substitute as follows:
    - Discard the prefix, if any
    - Convert the hexadecimal to a byte string

Note that encoding is stricter than decoding, which may not return
a valid UTF8 byte string.

When run as a command-line tool, this tool reads from stdin and writes
to stdout, encoding or decoding the streams as specified by options.
"""

import sys
import re

def dump(utf8Str, fileObj, prefix='x'):
    """
    Dumps the hescii encoding of a utf-8 byte string to fileObj.
       
    Args:
        utf8Str: A utf-8 byte string
        fileObj: A python file open for writing
        prefix: string to prefix all encoded hex values. Default 'x'
        
    Returns:
        Nothing
    """
    fileObj.write(dumps(utf8Str, prefix))
    fileObj.flush()

def dumps(utf8Str, prefix='x'):
    """
    Returns the hescii encoding of a utf-8 byte string.

    Args:
        utf8Str: A utf-8 byte string
        prefix: string to prefix all encoded hex values. Default 'x'
      
    Returns:
        A hescii string
    """
    unicodeStr = utf8Str.decode('utf8')
    def repl_whitespace(char):
        if char.isspace() and char > u'\u007F':
            return u'\u0020'
        else:
            return char
    asciiWhitespaceStr = ''.join(map(repl_whitespace, unicodeStr))
    def repl_encode(match):
        s = match.group()
        return prefix + s.encode('utf8').encode('hex')
    hesciiStr = re.sub(r'\S+', repl_encode, asciiWhitespaceStr)
    return hesciiStr.encode('ascii')

def load(fileObj, prefix='x'):
    """
    Loads a hescii-encoded file and returns the utf-8 byte string.
        
    Args:
        fileObj: A python file open for reading
        prefix: string used to prefix all encoded hex values. Default 'x'
        
    Returns:
        A utf-8 byte string
    """
    return loads(fileObj.read(), prefix)

def loads(hesciiStr, prefix='x'):
    """
    Takes a hescii-encoded string and returns the utf-8 byte string.

    Args:
        hesciiStr: a hescii-encoded string
        prefix: string used to prefix all encoded hex values. Default 'x'
        
    Returns:
        A utf-8 byte string
        
    """
    def repl(match):
        s = match.group()
        return s[len(prefix):].decode('hex')
    pattern = prefix + r'([0123456789abcdefABCDEF][0123456789abcdefABCDEF])+'
    return re.sub(pattern, repl, hesciiStr)

if __name__ == '__main__':
    """
    Take an input file and return the hex encoding of its contents,
    leaving ascii whitespace unchanged
    """
    # Parse commandline arguments
    import argparse
    parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter,
                                     description=DESCRIPTION)
    parser.add_argument('-c', '--column', default=3, type=int,
                        help='Column to use for pronunciation\n' + \
                        'Default: 3')
    parser.add_argument('-p', '--prefix', default='x',
                        help='Specify prefix for hex values.\n' + \
                        'Default: x')
    parser.add_argument('-d', '--decode', action='store_true', help="Decode from hescii (not yet working)")
    parser.add_argument('-s', '--syllable_prediction', action='store_true', help='Predict syllables (must have . syllable separator)')
    parser.add_argument('-t', '--syllable_phone_separator', default='_', help='When predicting syllables, concatenate phones with this separator')
    parser.add_argument('-m', '--syllable_marks', action='store_true', help='Keep syllable marks')
    parser.add_argument('--version', action='version', version='$Id: hescii.py 336 2013-01-18 18:22:37Z arlo $')
    args = parser.parse_args()
    
    # Set params from commandline
    prefix = args.prefix
    decode = args.decode
    column = args.column-1;
    syllable_marks = args.syllable_marks;
    syllable_separator = args.syllable_phone_separator;
    syllable_prediction = args.syllable_prediction;

    # read from stdin
    for line in sys.stdin:
        sline=line.rstrip().split('\t')
        uword = sline[0].decode('utf8').lower()
        # remove lines that start with < (e.g. <hes>)
        # TODO: HANDLE MORPHS
        #morphs=uword.split('__')
        if (len(sline)>1):
            if (syllable_prediction):
                # merge phones into syllables
                pron1 = re.sub(r'[%] ',"",sline[column].strip())

                pparts=pron1.split(' # ')
                for pindex,p in enumerate(pparts):
                    syls=p.split(' . ')
                    for sindex,s in enumerate(syls):
                        syls[sindex]=re.sub(r'  *',syllable_separator,s)
                    if (syllable_marks):
                        pparts[pindex]=' . '.join(syls)
                    else:
                        pparts[pindex]=' '.join(syls)
                pron1=' # '.join(pparts)
            else:
                if (syllable_marks):
                    pron1 = re.sub(r'[%] ',"",sline[column].strip())
                else:
                    pron1 = re.sub(r'[%\.] ',"",sline[column].strip())

            pron = re.sub(r'  *'," ",pron1)
        else:
            pron = ''

        if (re.search(r'(^__|__$)',uword)):
            subwords=[uword]
            subprons=[pron]
        else:
            subwords = uword.split('_')
            subprons = pron.split('#')

        def repl_encode(match):
            s = match.group()
            return 'x' + s.encode('utf8').encode('hex')

        if (len(subwords) == len(subprons)):
            for swindex,subword in enumerate(subwords):
                if (len(subwords)>1 and len(subword)==1):
                    if (subword > u'\u007F'):
                        subword=re.sub(r'\S+', repl_encode, subword)
                    print(subword+'+\t'+subprons[swindex].strip())
                else:
                    letters=list(subword)
                    for index,l in enumerate(letters):
                        if (l > u'\u007F'):
                            hesciiStr = re.sub(r'\S+', repl_encode, l)

                            letters[index]=hesciiStr.encode('ascii')
                    print(' '.join(letters)+'\t'+subprons[swindex].strip())
        elif (len(subprons)==1):
            output=[]
            for swindex,subword in enumerate(subwords):
                if (len(subword)==1 and
                    subword>='a' and
                    subword<='z'):
                    swout=''
                    if (swindex>0):
                        swout='_ '
                    swout+=subword+'+'
#                    if (swindex<len(subwords)-1):
#                        swout+=' _'
                    output.append(swout)
                else:
                    letters=list(subword)
                    for index,l in enumerate(letters):
                        if (l > u'\u007F'):
                            hesciiStr = re.sub(r'\S+', repl_encode, l)
                            letters[index]=hesciiStr.encode('ascii')
                    if (len(output)>0):
                        output.append('_')
                    output.append(' '.join(letters))
            print(' '.join(output)+'\t'+subprons[0].strip())
