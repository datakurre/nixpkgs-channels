{ stdenv, fetchurl, libiconv, recode, buildPackages }:

stdenv.mkDerivation rec {
  pname = "enca";
  version = "2018-10-16";

  src = fetchurl {
    url = "https://github.com/nijel/enca/archive/5de465b25a7e5dd432bf9b10f253391a1139e1c4.tar.gz";
    sha256 = "0qdffzvq2h8ilnym5kcll3sr08db4igk9rh2p0zapj9bblp5p2bp";
  };

  preConfigure = ''
    export CC_FOR_BUILD=${buildPackages.stdenv.cc}/bin/cc
  '';

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  buildInputs = [ recode libiconv ];

  meta = with stdenv.lib; {
    description = "Detects the encoding of text files and reencodes them";

    longDescription = ''
        Enca detects the encoding of text files, on the basis of knowledge
        of their language. It can also convert them to other encodings,
        allowing you to recode files without knowing their current encoding.
        It supports most of Central and East European languages, and a few
        Unicode variants, independently on language.
    '';

    license = licenses.gpl2;
   
  };
}
