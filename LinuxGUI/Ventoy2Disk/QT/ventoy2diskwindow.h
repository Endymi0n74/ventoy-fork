#ifndef VENTOY2DISKWINDOW_H
#define VENTOY2DISKWINDOW_H

#include <QMainWindow>
#include <QActionGroup>
#include <QJsonDocument>
#include <QFile>
#include <QJsonObject>
#include <QJsonArray>
#include <QVector>
#include <QtGlobal>
#include <QDebug>
#include <QCloseEvent>
#include <QThread>
#include <QLabel>
#include "partcfgdialog.h"

QT_BEGIN_NAMESPACE
namespace Ui { class Ventoy2DiskWindow; }
QT_END_NAMESPACE

#define THREAD_TYPE_INSTALL             1
#define THREAD_TYPE_UPDATE              2

#define THREAD_MSG_PROGRESS_BAR         1
#define THREAD_MSG_INSTALL_FINISH       2
#define THREAD_MSG_UPDATE_FINISH        3

class MyQThread : public QThread
{
    Q_OBJECT
public:
    quint64 m_reserve_space;
    int m_index;
    int m_type;
    int m_secureboot;
    int m_align4K;
    bool m_running;
    void install_run();
    void update_run();

    explicit MyQThread(QObject *parent = nullptr);
protected:
    void run();
signals:
    void thread_event(int msg, int data);
public slots:
};


class Ventoy2DiskWindow : public QMainWindow
{
    Q_OBJECT

public:
    Ventoy2DiskWindow(QWidget *parent = nullptr);
    ~Ventoy2DiskWindow();

    QActionGroup *m_part_group;
    QActionGroup *m_lang_group;
    QJsonArray m_lang_array;
    PartCfgDialog *m_partcfg;
    MyQThread *m_thread;

    void FillDeviceList(const QString &select);
    void OnInitWindow(void);
    void LoadLanguages();
    int lang_string(const QString &id, QString &str);
    void update_ui_language();
    void set_percent(int percent);

    // Regle la police du libelle pour que la version y tienne toujours.
    static void SetVersionLabel(QLabel *label, const char *ver);
protected:
    void showEvent(QShowEvent *ev);
    void closeEvent(QCloseEvent *event);

private slots:

    void thread_event(int msg, int data);
    void part_style_check_action(QAction *act);
    void lang_check_action(QAction *act);

    void on_ButtonInstall_clicked();

    void on_ButtonUpdate_clicked();

    void on_ButtonRefresh_clicked();

    void on_comboBoxDevice_currentIndexChanged(int index);    

    void on_actionPartition_Configuration_triggered();

    void on_actionClear_Ventoy_triggered();

    void on_actionShow_All_Devices_toggled(bool arg1);

    void on_actionSecure_Boot_Support_triggered();

private:
    Ui::Ventoy2DiskWindow *ui;


};

#define _LANG_STR(id) obj.value(id).toString()
// La taille et la graisse NE sont plus dans le HTML : elles sont choisies a
// l'execution par SetVersionLabel() pour que le texte tienne toujours dans le
// libelle. La couleur reste fixee ici.
#define VERSION_FMT "<html><head/><body><p><span style=\" color:#ff0000;\">%s</span></p></body></html>"

#endif // VENTOY2DISKWINDOW_H
