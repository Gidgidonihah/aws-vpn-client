class OpenvpnAws < Formula

  desc "SSL/TLS VPN implementing OSI layer 2 or 3 secure network extension"
  homepage "https://openvpn.net/community/"
  url "https://swupdate.openvpn.org/community/releases/openvpn-2.6.19.tar.gz"
  mirror "https://build.openvpn.net/downloads/releases/openvpn-2.6.19.tar.gz"
  sha256 "13702526f687c18b2540c1a3f2e189187baaa65211edcf7ff6772fa69f0536cf"
  license "GPL-2.0-only" => { with: "openvpn-openssl-exception" }

  livecheck do
    url "https://openvpn.net/community-downloads/"
    regex(/href=.*?openvpn[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

patch :DATA

  depends_on "pkg-config" => :build
  depends_on "lz4"
  depends_on "lzo"

  depends_on "openssl@3"
  depends_on "pkcs11-helper"

  on_linux do
    depends_on "linux-pam"
    depends_on "net-tools"
  end

  def install
    system "./configure", "--disable-debug",
                          "--disable-dependency-tracking",
                          "--disable-silent-rules",
                          "--with-crypto-library=openssl",
                          # "--enable-pkcs11", # Disable to get working. See https://github.com/samm-git/aws-vpn-client/issues/7#issuecomment-1741534919
                          "--prefix=#{prefix}"
    inreplace "sample/sample-plugins/Makefile" do |s|
      s.gsub! HOMEBREW_LIBRARY/"Homebrew/shims/mac/super/pkg-config",
              Formula["pkg-config"].opt_bin/"pkg-config"
      # Disabled to get functional. See https://github.com/samm-git/aws-vpn-client/issues/7#issue-866856655
      # s.gsub! HOMEBREW_LIBRARY/"Homebrew/shims/mac/super/sed",
      #         "/usr/bin/sed"
    end
    system "make", "install"

    inreplace "sample/sample-config-files/openvpn-startup.sh",
              "/etc/openvpn", "#{etc}/openvpn"

    (doc/"samples").install Dir["sample/sample-*"]
    (etc/"openvpn").install doc/"samples/sample-config-files/client.conf"
    (etc/"openvpn").install doc/"samples/sample-config-files/server.conf"

    # Disabled to get functional. See https://github.com/samm-git/aws-vpn-client/issues/7#issue-866856655
    # We don't use mbedtls, so this file is unnecessary & somewhat confusing.
    # rm doc/"README.mbedtls"
  end

  def post_install
    (var/"run/openvpn").mkpath
  end

  # Option deprecated, nor is it required
  # plist_options startup: true

  def plist
    <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd";>
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{opt_sbin}/openvpn</string>
          <string>--config</string>
          <string>#{etc}/openvpn/openvpn.conf</string>
        </array>
        <key>OnDemand</key>
        <false/>
        <key>RunAtLoad</key>
        <true/>
        <key>TimeOut</key>
        <integer>90</integer>
        <key>WatchPaths</key>
        <array>
          <string>#{etc}/openvpn</string>
        </array>
        <key>WorkingDirectory</key>
        <string>#{etc}/openvpn</string>
      </dict>
      </plist>
    EOS
  end

  test do
    system sbin/"openvpn", "--show-ciphers"
  end
end

__END__
diff --git i/src/openvpn/buffer.h w/src/openvpn/buffer.h
index d988ef2..3760175 100644
--- i/src/openvpn/buffer.h
+++ w/src/openvpn/buffer.h
@@ -27,7 +27,7 @@
 #include "basic.h"
 #include "error.h"

-#define BUF_SIZE_MAX 1000000
+#define BUF_SIZE_MAX 1 << 21

 /*
  * Define verify_align function, otherwise
diff --git i/src/openvpn/common.h w/src/openvpn/common.h
index 3a84541..61ee72e 100644
--- i/src/openvpn/common.h
+++ w/src/openvpn/common.h
@@ -66,7 +66,7 @@ typedef unsigned long ptr_type;
  * maximum size of a single TLS message (cleartext).
  * This parameter must be >= PUSH_BUNDLE_SIZE
  */
-#define TLS_CHANNEL_BUF_SIZE 2048
+#define TLS_CHANNEL_BUF_SIZE 1 << 18

 /* TLS control buffer minimum size
  *
diff --git i/src/openvpn/error.h w/src/openvpn/error.h
index ab2872a..cb0c68e 100644
--- i/src/openvpn/error.h
+++ w/src/openvpn/error.h
@@ -34,7 +34,10 @@
 #if defined(ENABLE_PKCS11) || defined(ENABLE_MANAGEMENT)
 #define ERR_BUF_SIZE 10240
 #else
-#define ERR_BUF_SIZE 1280
+/*
+ * Increase the error buffer size to 256 KB.
+ */
+#define ERR_BUF_SIZE 1 << 18
 #endif

 struct gc_arena;
diff --git i/src/openvpn/manage.c w/src/openvpn/manage.c
index 0e4afa2..962441c 100644
--- i/src/openvpn/manage.c
+++ w/src/openvpn/manage.c
@@ -2246,7 +2246,7 @@ man_read(struct management *man)
     /*
      * read command line from socket
      */
-    unsigned char buf[256];
+    unsigned char buf[MANAGEMENT_SOCKET_READ_BUFFER_SIZE];
     int len = 0;

 #ifdef TARGET_ANDROID
@@ -2582,7 +2582,7 @@ man_connection_init(struct management *man)
          * Allocate helper objects for command line input and
          * command output from/to the socket.
          */
-        man->connection.in = command_line_new(1024);
+        man->connection.in = command_line_new(COMMAND_LINE_OPTION_BUFFER_SIZE);
         man->connection.out = buffer_list_new();

         /*
diff --git i/src/openvpn/manage.h w/src/openvpn/manage.h
index 1896510..7284f10 100644
--- i/src/openvpn/manage.h
+++ w/src/openvpn/manage.h
@@ -55,9 +55,12 @@
 #define MANAGEMENT_VERSION                      5
 #define MANAGEMENT_N_PASSWORD_RETRIES           3
 #define MANAGEMENT_LOG_HISTORY_INITIAL_SIZE   100
-#define MANAGEMENT_ECHO_BUFFER_SIZE           100
+#define MANAGEMENT_ECHO_BUFFER_SIZE           8192
 #define MANAGEMENT_STATE_BUFFER_SIZE          100

+#define COMMAND_LINE_OPTION_BUFFER_SIZE OPTION_PARM_SIZE
+#define MANAGEMENT_SOCKET_READ_BUFFER_SIZE OPTION_PARM_SIZE
+
 /*
  * Management-interface-based deferred authentication
  */
diff --git i/src/openvpn/misc.h w/src/openvpn/misc.h
index 022498c..3e7cd3e 100644
--- i/src/openvpn/misc.h
+++ w/src/openvpn/misc.h
@@ -66,7 +66,10 @@ struct user_pass
 #ifdef ENABLE_PKCS11
 #define USER_PASS_LEN 4096
 #else
-#define USER_PASS_LEN 128
+/*
+ * Increase the username and password length size to 128KB.
+ */
+#define USER_PASS_LEN 1 << 17
 #endif
     /* Note that username and password are expected to be null-terminated */
     char username[USER_PASS_LEN];
diff --git i/src/openvpn/options.h w/src/openvpn/options.h
index 8482a4a..ddf35c1 100644
--- i/src/openvpn/options.h
+++ w/src/openvpn/options.h
@@ -54,8 +54,8 @@
 /*
  * Max size of options line and parameter.
  */
-#define OPTION_PARM_SIZE 256
-#define OPTION_LINE_SIZE 256
+#define OPTION_PARM_SIZE USER_PASS_LEN
+#define OPTION_LINE_SIZE OPTION_PARM_SIZE

 extern const char title_string[];

diff --git i/src/openvpn/ssl.c w/src/openvpn/ssl.c
index 9814bb3..dc1961d 100644
--- i/src/openvpn/ssl.c
+++ w/src/openvpn/ssl.c
@@ -1951,7 +1951,7 @@ tls_session_soft_reset(struct tls_multi *tls_multi)
 static bool
 write_empty_string(struct buffer *buf)
 {
-    if (!buf_write_u16(buf, 0))
+    if (!buf_write_u32(buf, 0))
     {
         return false;
     }
@@ -1966,7 +1966,7 @@ write_string(struct buffer *buf, const char *str, const int maxlen)
     {
         return false;
     }
-    if (!buf_write_u16(buf, len))
+    if (!buf_write_u32(buf, len))
     {
         return false;
     }
@@ -2327,6 +2327,10 @@ key_method_2_write(struct buffer *buf, struct tls_multi *multi, struct tls_sessi
         p2p_mode_ncp(multi, session);
     }

+    // Write key length in the first 4 octets of the buffer.
+    uint32_t length = BLEN(buf);
+    memcpy(buf->data, &length, sizeof(length));
+
     return true;

 error:
