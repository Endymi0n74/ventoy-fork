// Sonde de rendu de la fenetre Qt de Ventoy2Disk.
//
// Elle instancie la vraie forme issue de ventoy2diskwindow.ui, applique la
// vraie fonction Ventoy2DiskWindow::SetVersionLabel() (le code livre, pas une
// reimplementation), puis compare la largeur du texte rendu a la largeur du
// cadre declare. Un rendu PNG est ecrit pour un controle visuel.
//
// Compilee et lancee par dist/tests/test_gui_render.sh ; hors paquet.

#include <QApplication>
#include <QFont>
#include <QFontMetrics>
#include <QLabel>
#include <QMainWindow>
#include <QPixmap>
#include <QString>

#include <cstdio>

#include "ui_ventoy2diskwindow.h"
#include "ventoy2diskwindow.h"

// Definies dans main.cpp, que la sonde ne lie pas (il y a un main() rival).
#include "ventoy_define.h"
#include "ventoy_util.h"
char g_log_file[PATH_MAX];
char g_ini_file[PATH_MAX];

// 0 = le texte tient, 1 = debordement.
static int ProbeLabel(QLabel *label, const char *ver)
{
    if ((NULL == label) || (NULL == ver))
    {
        fprintf(stderr, "libelle ou version manquant\n");
        return 1;
    }

    const int frame = label->width();
    Ventoy2DiskWindow::SetVersionLabel(label, ver);

    const QFont font = label->font();
#if QT_VERSION >= QT_VERSION_CHECK(5, 11, 0)
    const int need = QFontMetrics(font).horizontalAdvance(QString::fromUtf8(ver));
#else
    const int need = QFontMetrics(font).width(QString::fromUtf8(ver));
#endif

    printf("%-22s cadre=%4dpx  police=%2dpt gras=%d  texte=%4dpx  marge=%+5dpx  %s\n",
           label->objectName().toUtf8().constData(), frame, font.pointSize(),
           (font.weight() >= QFont::Bold) ? 1 : 0, need, frame - need,
           (need <= frame) ? "OK" : "DEBORDE");

    return (need <= frame) ? 0 : 1;
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);

    const char *ver = (argc > 1) ? argv[1] : "1.1.18-Fork";
    const char *out = (argc > 2) ? argv[2] : "ventoy2disk-render.png";

    QMainWindow win;
    Ui::Ventoy2DiskWindow ui;
    ui.setupUi(&win);

    int rc = 0;
    rc |= ProbeLabel(ui.labelVentoyLocalVer, ver);
    rc |= ProbeLabel(ui.labelVentoyDeviceVer, ver);

    win.show();
    const QPixmap shot = win.grab();
    if (shot.isNull() || !shot.save(QString::fromUtf8(out)))
    {
        fprintf(stderr, "echec d'ecriture du rendu %s\n", out);
        return 2;
    }

    printf("rendu : %s (%dx%d)\n", out, shot.width(), shot.height());
    return rc;
}
