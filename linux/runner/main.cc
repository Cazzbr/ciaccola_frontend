#include "my_application.h"
#include <glib.h>

int main(int argc, char** argv) {
  // Suppress ATK accessibility socket warning when AT-SPI bus is not running.
  g_setenv("NO_AT_BRIDGE", "1", FALSE);
  // Suppress GDK cursor-theme warning for unmapped Flutter cursor names.
  g_setenv("GDK_BACKEND", "x11", FALSE);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
