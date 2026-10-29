package com.karandeep.sathi;

import java.io.*;

final class IO {
  static byte[] read(InputStream in, int limit) throws IOException {
    try (InputStream source = in;
        ByteArrayOutputStream out = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[8192];
      int n;
      while ((n = source.read(buffer)) != -1) {
        if (out.size() + n > limit) throw new IOException("File exceeds size limit");
        out.write(buffer, 0, n);
      }
      return out.toByteArray();
    }
  }
}
