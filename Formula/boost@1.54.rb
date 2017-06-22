class BoostAT154 < Formula
  desc "Collection of portable C++ source libraries"
  homepage "https://www.boost.org"
  revision 1

  stable do
    url "https://downloads.sourceforge.net/project/boost/boost/1.54.0/boost_1_54_0.tar.bz2"
    sha256 "047e927de336af106a24bceba30069980c191529fd76b8dff8eb9a328b48ae1d"
  end

  bottle do
    cellar :any
    sha256 "bf89ab11c1ceab224a5ece4629987b4d8d137c5c3506a4577301f70b05d0ea97" => :sierra
    sha256 "30bb554952cdbcc445b247f570243c31ab4cafebf55bcfe96b9cabcb5ca2f716" => :el_capitan
    sha256 "9a3929bec0e9e9db36e005f57193433ac6b5ff9ff86b2ed3262b975d58488c19" => :yosemite
  end

  env :userpaths

  option "with-icu", "Build regexp engine with icu support"
  option "without-single", "Disable building single-threading variant"
  option "without-static", "Disable building static library variant"
  option "with-mpi", "Build with MPI support"
  option :cxx11

  if build.with? "icu"
    if build.cxx11?
      depends_on "icu4c" => "c++11"
    else
      depends_on "icu4c"
    end
  end

  if build.with? "mpi"
    if build.cxx11?
      depends_on "open-mpi" => "c++11"
    else
      depends_on :mpi => [:cc, :cxx, :optional]
    end
  end

  def install
    # https://svn.boost.org/trac/boost/ticket/8841
    if build.with?("mpi") && build.with?("single")
      raise <<-EOS.undent
        Building MPI support for both single and multi-threaded flavors
        is not supported.  Please use "--with-mpi" together with
        "--without-single".
      EOS
    end

    # Force boost to compile using the appropriate GCC version.
    open("user-config.jam", "a") do |file|
      file.write "using darwin : : #{ENV.cxx} ;\n"
      file.write "using mpi ;\n" if build.with? "mpi"
    end

    # we specify libdir too because the script is apparently broken
    bootstrap_args = ["--prefix=#{prefix}", "--libdir=#{lib}"]

    if build.with? "icu"
      icu4c_prefix = Formula["icu4c"].opt_prefix
      bootstrap_args << "--with-icu=#{icu4c_prefix}"
    else
      bootstrap_args << "--without-icu"
    end

    # Handle libraries that will not be built.
    without_libraries = ["python"]

    # The context library is implemented as x86_64 ASM, so it
    # won't build on PPC or 32-bit builds
    # see https://github.com/Homebrew/homebrew/issues/17646
    if Hardware::CPU.ppc? || Hardware::CPU.is_32_bit?
      without_libraries << "context"
      # The coroutine library depends on the context library.
      without_libraries << "coroutine"
    end

    # Boost.Log cannot be built using Apple GCC at the moment. Disabled
    # on such systems.
    without_libraries << "log" if ENV.compiler == :gcc || ENV.compiler == :llvm
    without_libraries << "mpi" if build.without? "mpi"

    bootstrap_args << "--without-libraries=#{without_libraries.join(",")}"

    # layout should be synchronized with boost-python
    args = ["--prefix=#{prefix}",
            "--libdir=#{lib}",
            "-d2",
            "-j#{ENV.make_jobs}",
            "--layout=tagged",
            "--user-config=user-config.jam",
            "install"]

    if build.with? "single"
      args << "threading=multi,single"
    else
      args << "threading=multi"
    end

    if build.with? "static"
      args << "link=shared,static"
    else
      args << "link=shared"
    end

    # Trunk starts using "clang++ -x c" to select C compiler which breaks C++11
    # handling using ENV.cxx11. Using "cxxflags" and "linkflags" still works.
    if build.cxx11?
      args << "cxxflags=-std=c++11"
      if ENV.compiler == :clang
        args << "cxxflags=-stdlib=libc++" << "linkflags=-stdlib=libc++"
      end
    end

    system "./bootstrap.sh", *bootstrap_args
    system "./b2", *args
  end

  def caveats
    s = ""
    # ENV.compiler doesn't exist in caveats. Check library availability
    # instead.
    if Dir["#{lib}/libboost_log*"].empty?
      s += <<-EOS.undent

      Building of Boost.Log is disabled because it requires newer GCC or Clang.
      EOS
    end

    if Hardware::CPU.ppc? || Hardware::CPU.is_32_bit?
      s += <<-EOS.undent

      Building of Boost.Context and Boost.Coroutine is disabled as they are
      only supported on x86_64.
      EOS
    end

    s
  end

  test do
    (testpath/"test.cpp").write <<-EOS.undent
      #include <boost/algorithm/string.hpp>
      #include <string>
      #include <vector>
      #include <assert.h>
      using namespace boost::algorithm;
      using namespace std;

      int main()
      {
        string str("a,b");
        vector<string> strVec;
        split(strVec, str, is_any_of(","));
        assert(strVec.size()==2);
        assert(strVec[0]=="a");
        assert(strVec[1]=="b");
        return 0;
      }
    EOS
    system ENV.cxx, "test.cpp", "-std=c++1y", "-lboost_system", "-o", "test"
    system "./test"
  end
end
