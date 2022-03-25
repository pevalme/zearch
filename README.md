# Regular Expression Search on Compressed Text

What is it?
**zearch** is a regular expression engine that takes in input a regular expression and a grammar-based compressed text and returns every line of the uncompressed text containing a match for the regular expression.

**zearch** is the implementation of an algorithm presented at the Data Compression Conference (DCC) in 2019. A link to the article is given [here](https://doi.org/10.1109/DCC.2019.00061).

## Limitations

- no match across lines
- no support invert match option
- only regular languages (like RE2) → e.g. no backreferences
- no zero-width character
- no named character classes (e.g. alnum, digit, lower,…)
- no UTF8 support, only ASCII characters
- no highlighted output, only matching line are reported in full

## Compiling

### Installing libfa
Instal the tools and libraries required to build **augeas** (besides the usual tools: gcc, autoconf, automake etc.)
```
sudo apt-get install bison, flex, readline-devel, libxml2-devel
```

Clone the [*augeas project*](https://github.com/hercules-team/augeas) repository.
```
git clone git@github.com:hercules-team/augeas.git
```
From the root folder run
```
./autogen.sh
make
sudo make install
```

Finally, update the library path so that **zearch** can find **libfa**
```
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
export LD_LIBRARY_PATH
```

### Compiling Zearch
From the root folder of this repository run `make zearch stats debug` which generates three executables:
* *zearch* is the main program.
* *stats* works as zearch but produces some statistical information about memory usage.
* *debug* prints a lot of information for debugging through stderr.

These three tools are invoked in the same way:
```
./{zearch,debug,stats} [-m] <option> <input_regex> <input_file>
```
where
* *-m* is an optional argument. When present, the program will determinize and minimize the automaton, following the algorithm used by *libfa*. Note that this option does not always improves performance.
* *option* can be `-c`, `-l`, `-a` or `-b` to print the number of matching lines, the matching lines, both of them or simply inform about whether there is (at least) one match or not respectively.
* *input_regex* is a regular expression following the format accepted by *libfa*.
* *input_file* is a [repair](https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz)-compressed file.


## Comparison with other tools
We have compared the performance of **zearch** with the state of the art approach for regular expression matching on compressed text.
Due to the limited functionality of our tool, the comparison only considers the running time required by these tools to report the number of lines in the original file containing a match.
For the experiments the state of the art is represented by the following command
```
{lz4,zstd} -dc compressed_file | {grep,rg,hyperscan} -c regex
```
The experiments show that our tool outperforms the state of the art, even though decompression and search are done in parallel.
The detailed results of this comparison are available [here](https://pevalme.github.io/zearch/graphs/index.html)
