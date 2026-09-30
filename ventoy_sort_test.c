/*
 * ventoy_sort_test.c
 *
 * Standalone correctness + basic perf harness for the Ventoy GRUB
 * menu-build image sort in:
 *   grub-core/ventoy/ventoy_cmd.c
 *
 * Targets:
 *   - ventoy_cmp_img()
 *   - ventoy_swap_img()
 *   - ventoy_img_merge()
 *   - ventoy_img_msort()
 *
 * This file is a local test companion and does NOT include or modify the
 * GRUB build tree. It only provides a minimal compatibility shim for the
 * GRUB APIs used by the sort cluster in this checkout.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ------------------------------------------------------------------ */
/* Minimal GRUB compatibility shim (mirrored from this checkout only) */
/* ------------------------------------------------------------------ */

#define grub_uint8_t  uint8_t
#define grub_uint32_t uint32_t
#define grub_uint64_t uint64_t
#define grub_size_t   size_t
#define grub_ssize_t  ssize_t
#define grub_int_t    int
#define grub_err_t    int

#define GRUB_ERR_NONE           0
#define GRUB_ERR_BAD_ARGUMENT  -1

#define GRUB_FILE_TYPE_NO_DECOMPRESS 0
#define GRUB_FILE_TYPE_LINUX_INITRD 1
#define VENTOY_CMD_RETURN(err)  do { return (err); } while (0)

#define VTOY_MAX_SCRIPT_BUF (4 * 1024 * 1024)

typedef struct img_info img_info;

struct img_info {
    int pathlen;
    char path[512];
    char name[256];

    const char *alias;
    const char *tip1;
    const char *tip2;
    const char *class;
    const char *menu_prefix;

    int id;
    int type;
    int plugin_list_index;
    grub_uint64_t size;
    int select;
    int unsupport;

    void *parent;

    struct img_info *next;
    struct img_info *prev;
};

int g_sort_case_sensitive = 0;
int g_plugin_image_list = 0;

#define VENTOY_IMG_WHITE_LIST 1
#define VENTOY_IMG_BLACK_LIST 2

/* ------------------------------------------------------------------ */
/* img_iterator_node shim (mirrors grub-core/ventoy/ventoy_cmd.c)     */
/* ------------------------------------------------------------------ */

typedef struct img_iterator_node img_iterator_node;

struct img_iterator_node {
    struct img_iterator_node *next;
    const char *dir;
    int dirlen;
    int plugin_list_index;
};

static inline int __attribute__((used)) grub_islower(int c)
{
    return (c >= 'a' && c <= 'z');
}

#define grub_min(a, b) (((a) < (b)) ? (a) : (b))

static void *grub_malloc(grub_size_t size)
{
    return malloc(size);
}

static void grub_free(void *p)
{
    free(p);
}

/* ------------------------------------------------------------------ */
/* Imported from ventoy_cmd.c (copied for standalone compilation)     */
/* ------------------------------------------------------------------ */

/*
 * Case-insensitive or case-sensitive comparison by image name.
 * Stable merge sort in this code uses <= 0, so equal keys preserve order.
 *
 * This mirrors the logic in grub-core/ventoy/ventoy_cmd.c::ventoy_cmp_img()
 * as present on the perf/menu-build branch.
 */
int ventoy_cmp_img(img_info *img1, img_info *img2)
{
    const char *s1 = img1->name;
    const char *s2 = img2->name;
    int c1 = 0;
    int c2 = 0;

    if (g_plugin_image_list == VENTOY_IMG_WHITE_LIST)
    {
        return (img1->plugin_list_index - img2->plugin_list_index);
    }

    for (s1 = img1->name, s2 = img2->name; *s1 && *s2; s1++, s2++)
    {
        c1 = (unsigned char )*s1;
        c2 = (unsigned char )*s2;

        if (g_sort_case_sensitive == 0)
        {
            if (grub_islower(c1))
                c1 = c1 - 'a' + 'A';
            if (grub_islower(c2))
                c2 = c2 - 'a' + 'A';
        }

        if (c1 != c2)
            return (c1 - c2);
    }

    if (*s1 == '\0' && *s2 == '\0')
        return 0;

    if (*s1 == '\0')
        return -1;
    else
        return 1;
}

/*
 * Directory-path comparison used by the menu-build tree walk.
 * Mirrors ventoy_cmd.c::ventoy_cmp_subdir():
 *   - compare dir[] cell-by-cell up to min(dirlen1, dirlen2) - 1
 *   - the shorter path's missing terminator is treated as 0, so a
 *     parent directory sorts before a deeper descendant when they
 *     share a prefix
 *   - in plugin-list (WHITE_LIST) mode the result is by
 *     plugin_list_index only
 */
static int ventoy_cmp_subdir(img_iterator_node *node1, img_iterator_node *node2)
{
    int i = 0;
    int c1 = 0;
    int c2 = 0;
    int len = 0;
    const char *s1 = node1->dir;
    const char *s2 = node2->dir;

    if (g_plugin_image_list == VENTOY_IMG_WHITE_LIST)
    {
        return (node1->plugin_list_index - node2->plugin_list_index);
    }

    len = grub_min(node1->dirlen, node2->dirlen);

    for (i = 0; i < len - 1; i++)
    {
        c1 = (unsigned char)s1[i];
        c2 = (unsigned char)s2[i];

        if (g_sort_case_sensitive == 0)
        {
            if (grub_islower(c1))
                c1 = c1 - 'a' + 'A';
            if (grub_islower(c2))
                c2 = c2 - 'a' + 'A';
        }

        if (c1 != c2)
            return (c1 - c2);
    }

    if (len == node1->dirlen)
    {
        c1 = 0;
    }

    if (len == node2->dirlen)
    {
        c2 = 0;
    }

    return (c1 - c2);
}

/*
 * Swap two img_info nodes in place without disturbing surrounding
 * next/prev links. The real code uses a static tmp struct for this.
 */
void ventoy_swap_img(img_info *img1, img_info *img2)
{
    img_info tmp;

    memcpy(&tmp, img1, sizeof(tmp));
    memcpy(img1, img2, sizeof(*img1));
    img1->next = tmp.next;
    img1->prev = tmp.prev;

    tmp.next = img2->next;
    tmp.prev = img2->prev;
    memcpy(img2, &tmp, sizeof(*img2));
}

/*
 * Stable merge sort on the img_info linked list (via next pointer).
 * Uses <= 0 for stability: equal elements keep their original relative order.
 * Recursion depth is O(log n); acceptable within the pre-boot memory budget.
 */
static img_info *ventoy_img_merge(img_info *a, img_info *b)
{
    img_info head;
    img_info *tail = &head;

    head.next = NULL;
    head.prev = NULL;

    while (a && b)
    {
        img_info *take;

        if (ventoy_cmp_img(a, b) <= 0)
        {
            take = a;
            a = a->next;
        }
        else
        {
            take = b;
            b = b->next;
        }

        take->next = NULL;
        take->prev = NULL;

        tail->next = take;
        take->prev = tail;
        tail = take;
    }

    if (a)
    {
        tail->next = a;
        a->prev = tail;
    }
    else if (b)
    {
        tail->next = b;
        b->prev = tail;
    }

    if (head.next)
    {
        head.next->prev = NULL;
    }

    return head.next;
}

static img_info *ventoy_img_msort(img_info *list, int n)
{
    img_info *a;
    img_info *b;

    if (n <= 1)
    {
        return list;
    }

    /* split into a = first n/2 elements, b = the rest */
    a = list;
    b = list;
    {
        int k = n / 2;
        while (k-- && b)
            b = b->next;
    }

    /* Terminate the first half so the two recursive calls operate on disjoint lists. */
    if (b)
    {
        img_info *prev_a = list;
        while (prev_a->next != b && prev_a->next)
            prev_a = prev_a->next;
        if (prev_a->next == b)
            prev_a->next = NULL;
    }

    a = ventoy_img_msort(a, n / 2);
    b = ventoy_img_msort(b, n - n / 2);
    return ventoy_img_merge(a, b);
}

/* ------------------------------------------------------------------ */
/* Helpers to build / teardown a linked list under test                */
/* ------------------------------------------------------------------ */

static void copy_name(char *dst, const char *src, size_t dstsz)
{
    size_t n = dstsz - 1;
    const char *s = src;
    char *d = dst;
    while (n-- && (*d = *s))
    {
        d++;
        s++;
    }
    *d = '\0';
}

static img_info *make_item(const char *name, int id, grub_uint64_t size)
{
    img_info *item = (img_info *)grub_malloc(sizeof(img_info));
    if (!item) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    memset(item, 0, sizeof(*item));
    copy_name(item->name, name, sizeof(item->name));
    item->id = id;
    item->size = size;
    item->next = NULL;
    item->prev = NULL;
    return item;
}

static void free_list(img_info *list)
{
    while (list) {
        img_info *next = list->next;
        grub_free(list);
        list = next;
    }
}

static int list_is_ordered(img_info *list)
{
    for (img_info *p = list; p && p->next; p = p->next) {
        if (ventoy_cmp_img(p, p->next) > 0)
            return 0;
    }
    return 1;
}

static int list_prev_pointers_valid(img_info *list)
{
    img_info *prev = NULL;
    for (img_info *p = list; p; prev = p, p = p->next) {
        if (p->prev != prev)
            return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* Optional perf comparison (off by default; does not touch GRUB tree) */
/* ------------------------------------------------------------------ */
#ifndef VENTOY_SORT_TEST_PERF
#define VENTOY_SORT_TEST_PERF 0
#endif

/* Number of inner repetitions per timed measurement (perf builds);
 * parsed in main() for all builds so --reps can be rejected loudly in
 * non-perf binaries. 0 = auto-calibrate to ~50 ms blocks. */
static int g_perf_reps = 0;

#if VENTOY_SORT_TEST_PERF

/* Naive alternative: insertion sort over an array of pointers. */
static img_info *naive_insertion_sort_ptr_array(img_info **arr, int n)
{
    int i, j;
    img_info *key;

    for (i = 1; i < n; i++)
    {
        key = arr[i];
        j = i - 1;

        while (j >= 0 && ventoy_cmp_img(arr[j], key) > 0)
        {
            arr[j + 1] = arr[j];
            j--;
        }

        arr[j + 1] = key;
    }

    if (n > 0)
        arr[0]->prev = NULL;

    for (j = 0; j < n - 1; j++)
    {
        arr[j]->next = arr[j + 1];
        arr[j + 1]->prev = arr[j];
    }

    if (n > 0)
        arr[n - 1]->next = NULL;

    return arr[0];
}

/* Build a fresh disjoined list from a pointer array. */
static img_info *list_from_ptr_array(img_info **arr, int n)
{
    if (n <= 0)
        return NULL;

    for (int i = 0; i < n; i++)
    {
        arr[i]->prev = (i > 0) ? arr[i - 1] : NULL;
        arr[i]->next = (i < n - 1) ? arr[i + 1] : NULL;
    }

    return arr[0];
}

/* High-resolution timer helpers for perf measurements.
 *
 * On Windows this uses QueryPerformanceCounter (typically sub-microsecond
 * resolution) instead of clock() (~1 ms granularity, which quantized all
 * small-N timings to 0.000/0.001). The Win32 functions are declared
 * directly rather than pulling in <windows.h>: the GRUB compatibility
 * shim in this file defines macros (grub_min, etc.) that windows.h
 * conflicts with.
 *
 * Non-Windows builds fall back to clock(). */

#if defined(_WIN32) || defined(_WIN64)
extern int __stdcall QueryPerformanceCounter(unsigned long long *counter);
extern int __stdcall QueryPerformanceFrequency(unsigned long long *frequency);
#endif

static int perf_test_sizes[] = { 32, 128, 512, 2048, 8192, 16384 };
static const int perf_test_sizes_len = (int)(sizeof(perf_test_sizes) / sizeof(perf_test_sizes[0]));

static double perf_timestamp(void)
{
#if defined(_WIN32) || defined(_WIN64)
    unsigned long long counter = 0;
    QueryPerformanceCounter(&counter);
    return (double)counter;
#else
    return (double)clock();
#endif
}

static double perf_seconds_elapsed(double t0, double t1)
{
#if defined(_WIN32) || defined(_WIN64)
    unsigned long long frequency = 0;
    (void)QueryPerformanceFrequency(&frequency);
    if (frequency == 0)
        frequency = 1;  /* defensive; QPF never returns 0 on real systems */
    return (t1 - t0) / (double)frequency;
#else
    return (t1 - t0) / (double)CLOCKS_PER_SEC;
#endif
}

/* Accumulator for sweep statistics. */
typedef struct perf_stats {
    double sum;
    double min;
    double max;
    int runs;
} perf_stats;

static void perf_stats_add(perf_stats *st, double v)
{
    if (st->runs == 0 || v < st->min)
        st->min = v;
    if (st->runs == 0 || v > st->max)
        st->max = v;
    st->sum += v;
    st->runs++;
}

/* Inner-repetition timing: each measurement runs K rounds of
 * (restore initial ordering + sort) and reports the per-sort average,
 * which stabilizes the sub-10us small-N numbers against one-off
 * scheduling noise. K is auto-calibrated so one measurement block
 * takes ~50 ms, or can be forced with --reps. The restore cost (a
 * relink for the list sorters, a pointer-array memcpy for the array
 * sorters) is O(n) and stays inside the timed block for both
 * algorithms alike, so comparisons remain fair. Restoring is what
 * keeps every round on the same RANDOM workload: without it, reps
 * 2..K would sort already-sorted data, which flatters the O(n)
 * insertion sort enormously. */

#define PERF_TARGET_BLOCK_SECS 0.05
#define PERF_MAX_REPS 65536

static int perf_pick_reps(double secs_one_round)
{
    int reps;
    if (g_perf_reps > 0)
        return g_perf_reps;
    if (secs_one_round <= 0.0)
        secs_one_round = 1e-9;
    reps = (int)(PERF_TARGET_BLOCK_SECS / secs_one_round);
    if (reps < 1)
        reps = 1;
    if (reps > PERF_MAX_REPS)
        reps = PERF_MAX_REPS;
    return reps;
}

static double perf_time_img_merge(img_info **arr, int N, int reps)
{
    double t0 = perf_timestamp();
    for (int k = 0; k < reps; k++)
    {
        list_from_ptr_array(arr, N);
        (void)ventoy_img_msort(arr[0], N);
    }
    return perf_seconds_elapsed(t0, perf_timestamp()) / (double)reps;
}

static double perf_time_img_naive(img_info **arr, img_info **saved, int N, int reps)
{
    double t0 = perf_timestamp();
    for (int k = 0; k < reps; k++)
    {
        memcpy(arr, saved, (size_t)N * sizeof(img_info *));
        (void)naive_insertion_sort_ptr_array(arr, N);
    }
    return perf_seconds_elapsed(t0, perf_timestamp()) / (double)reps;
}

static int perf_img_once(int N, double *t_merge, double *t_naive)
{
    int failed = 0;
    img_info **arr_a = (img_info **)malloc(N * sizeof(img_info *));
    img_info **arr_b = (img_info **)malloc(N * sizeof(img_info *));
    img_info **saved_b = (img_info **)malloc(N * sizeof(img_info *));

    if (!arr_a || !arr_b || !saved_b)
    {
        fprintf(stderr, "PERF: out of memory at N=%d\n", N);
        free(arr_a); free(arr_b); free(saved_b);
        return 1;
    }
    for (int i = 0; i < N; i++)
    {
        char name[64];
        snprintf(name, sizeof(name), "%06u.iso", (unsigned int)(rand() % 500000));
        arr_a[i] = make_item(name, i, (grub_uint64_t)rand());
        arr_b[i] = make_item(name, i, (grub_uint64_t)rand());
    }

    /* Shuffle arr_a to match arr_b ordering. */
    for (int i = 0; i < N; i++)
    {
        if (rand() % 2)
        {
            char tmp[256];
            memcpy(tmp, arr_a[i]->name, sizeof(tmp));
            memcpy(arr_a[i]->name, arr_b[i]->name, sizeof(arr_a[i]->name));
            memcpy(arr_b[i]->name, tmp, sizeof(tmp));
        }
    }
    /* Make names identical for fair comparison. */
    for (int i = 0; i < N; i++)
        memcpy(arr_b[i]->name, arr_a[i]->name, sizeof(arr_b[i]->name));

    /* Preserve the initial pointer ordering of the array-based naive
     * sort: it permutes its array in place, so each timed round
     * restores it from this copy. The merge path needs no saved copy
     * because list_from_ptr_array() rebuilds the list from array order
     * every round. */
    memcpy(saved_b, arr_b, (size_t)N * sizeof(img_info *));

    /* ---- merge sort ---- */
    {
        int reps = perf_pick_reps(perf_time_img_merge(arr_a, N, 1));
        *t_merge = perf_time_img_merge(arr_a, N, reps);
        fprintf(stderr, "PERF: N=%d merge reps=%d\n", N, reps);

        /* Untimed correctness check on the same nodes. */
        list_from_ptr_array(arr_a, N);
        img_info *out = ventoy_img_msort(arr_a[0], N);
        if (!list_is_ordered(out) || !list_prev_pointers_valid(out))
        {
            fprintf(stderr, "PERF: merge sort failed correctness for N=%d\n", N);
            failed = 1;
        }
        free_list(out);
    }

    /* ---- insertion sort ---- */
    {
        int reps = perf_pick_reps(perf_time_img_naive(arr_b, saved_b, N, 1));
        *t_naive = perf_time_img_naive(arr_b, saved_b, N, reps);

        /* No-restore control: time K rounds of the memcpy restore alone
         * to quantify how much of the naive timing is harness overhead
         * rather than sort work. Expected share is small (restore is
         * O(n) memcpy vs O(n^2) compare-swap), and it inflates both
         * algorithms' absolute numbers, never their ranking. */
        {
            double t0c = perf_timestamp();
            for (int k = 0; k < reps; k++)
                memcpy(arr_b, saved_b, (size_t)N * sizeof(img_info *));
            double restore_share =
                100.0 * (perf_seconds_elapsed(t0c, perf_timestamp()) / (double)reps)
                        / (*t_naive > 0.0 ? *t_naive : 1e-9);
            fprintf(stderr, "PERF: N=%d naive reps=%d restore_overhead=%.1f%%\n",
                    N, reps, restore_share);
        }

        memcpy(arr_b, saved_b, (size_t)N * sizeof(img_info *));
        img_info *out = naive_insertion_sort_ptr_array(arr_b, N);
        if (!list_is_ordered(out) || !list_prev_pointers_valid(out))
        {
            fprintf(stderr, "PERF: insertion sort failed correctness for N=%d\n", N);
            failed = 1;
        }
        free_list(out);
    }

    free(saved_b);
    free(arr_a);
    free(arr_b);
    return failed;
}

static int perf_mode_run(void)
{
    int failed = 0;
    fprintf(stderr, "PERF: running optional comparison build path\n");

    for (int t = 0; t < perf_test_sizes_len; t++)
    {
        int N = perf_test_sizes[t];
        double t_merge = 0.0;
        double t_naive = 0.0;

        if (perf_img_once(N, &t_merge, &t_naive))
            failed = 1;
        printf("PERF merge N=%d time=%.6f sec\n", N, t_merge);
        printf("PERF naive N=%d time=%.6f sec\n", N, t_naive);
    }

    return failed;
}

/* Seed sweep: run the img workload over seeds 1..nseeds and report
 * mean/min/max per size. Raw per-seed timings go to stderr; the summary
 * goes to stdout for easy capture. */
static int perf_img_sweep(int nseeds)
{
    int failed = 0;
    perf_stats *st_merge = (perf_stats *)calloc((size_t)perf_test_sizes_len,
                                                sizeof(perf_stats));
    perf_stats *st_naive = (perf_stats *)calloc((size_t)perf_test_sizes_len,
                                                sizeof(perf_stats));

    if (!st_merge || !st_naive)
    {
        fprintf(stderr, "PERF: out of memory for sweep stats\n");
        free(st_merge);
        free(st_naive);
        return 1;
    }

    for (int s = 1; s <= nseeds; s++)
    {
        srand((unsigned int)s);
        for (int t = 0; t < perf_test_sizes_len; t++)
        {
            int N = perf_test_sizes[t];
            double t_merge = 0.0;
            double t_naive = 0.0;

            if (perf_img_once(N, &t_merge, &t_naive))
                failed = 1;
            perf_stats_add(&st_merge[t], t_merge);
            perf_stats_add(&st_naive[t], t_naive);
            fprintf(stderr, "SWEEP-IMG seed=%d N=%d merge=%.6f naive=%.6f sec\n",
                    s, N, t_merge, t_naive);
        }
    }

    for (int t = 0; t < perf_test_sizes_len; t++)
    {
        int N = perf_test_sizes[t];
        printf("SWEEP-IMG N=%d seeds=%d merge mean=%.9f min=%.9f max=%.9f | "
               "naive mean=%.9f min=%.9f max=%.9f sec\n",
               N, st_merge[t].runs,
               st_merge[t].sum / st_merge[t].runs,
               st_merge[t].min, st_merge[t].max,
               st_naive[t].sum / st_naive[t].runs,
               st_naive[t].min, st_naive[t].max);
    }

    free(st_merge);
    free(st_naive);
    return failed;
}

/* ------------------------------------------------------------------ */
/* perf: subdir-path sort comparison (mirrors menu-build tree walk)  */
/* ------------------------------------------------------------------ */

static img_iterator_node *perf_subdir_merge(img_iterator_node *a, img_iterator_node *b)
{
    img_iterator_node *out = NULL;
    img_iterator_node **tailp = &out;

    while (a && b)
    {
        img_iterator_node *take;

        if (ventoy_cmp_subdir(a, b) <= 0)
        {
            take = a;
            a = a->next;
        }
        else
        {
            take = b;
            b = b->next;
        }

        take->next = NULL;
        *tailp = take;
        tailp = &take->next;
    }

    *tailp = (a ? a : b);
    return out;
}

static img_iterator_node *perf_subdir_msort(img_iterator_node *list, int n)
{
    img_iterator_node *a;
    img_iterator_node *b;

    if (n <= 1)
        return list;

    a = list;
    b = list;
    {
        int k = n / 2;
        while (k-- && b)
            b = b->next;
    }

    if (b)
    {
        img_iterator_node *prev_a = list;
        while (prev_a->next != b && prev_a->next)
            prev_a = prev_a->next;
        if (prev_a->next == b)
            prev_a->next = NULL;
    }

    a = perf_subdir_msort(a, n / 2);
    b = perf_subdir_msort(b, n - n / 2);
    return perf_subdir_merge(a, b);
}

static img_iterator_node *naive_subdir_insertion_sort(img_iterator_node **arr, int n)
{
    int i, j;
    img_iterator_node *key;

    for (i = 1; i < n; i++)
    {
        key = arr[i];
        j = i - 1;

        while (j >= 0 && ventoy_cmp_subdir(arr[j], key) > 0)
        {
            arr[j + 1] = arr[j];
            j--;
        }

        arr[j + 1] = key;
    }

    for (j = 0; j < n - 1; j++)
        arr[j]->next = arr[j + 1];
    if (n > 0)
        arr[n - 1]->next = NULL;

    return arr[0];
}

static int perf_subdir_once(int N, double *t_merge, double *t_naive)
{
    int failed = 0;
    img_iterator_node **arr_a = (img_iterator_node **)
        malloc(N * sizeof(img_iterator_node *));
    img_iterator_node **arr_b = (img_iterator_node **)
        malloc(N * sizeof(img_iterator_node *));
    img_iterator_node **saved_b = (img_iterator_node **)
        malloc(N * sizeof(img_iterator_node *));

    if (!arr_a || !arr_b || !saved_b)
    {
        fprintf(stderr, "PERF-SUBDIR: out of memory at N=%d\n", N);
        free(arr_a); free(arr_b); free(saved_b);
        return 1;
    }

    /* Build subdir nodes with realistic-looking paths. */
    for (int i = 0; i < N; i++)
    {
        char buf[128];
        int depth = (rand() % 4) + 1;
        int pos = 0;
        buf[pos++] = '/';
        for (int d = 0; d < depth; d++)
        {
            int len = (rand() % 6) + 2;
            const char *dirstrs[] = {
                "boot", "grub", "ventoy", "iso", "images",
                "data", "tools", "EFI", "system", "extra"
            };
            const char *d = dirstrs[rand() % (sizeof(dirstrs) / sizeof(dirstrs[0]))];
            if (pos + 1 + len + 1 < (int)sizeof(buf))
            {
                memcpy(buf + pos, d, len);
                pos += len;
                buf[pos++] = '/';
            }
        }
        buf[pos] = '\0';

        arr_a[i] = (img_iterator_node *)grub_malloc(sizeof(img_iterator_node));
        arr_b[i] = (img_iterator_node *)grub_malloc(sizeof(img_iterator_node));
        if (!arr_a[i] || !arr_b[i])
        {
            fprintf(stderr, "PERF-SUBDIR: out of memory at N=%d\n", N);
            free(arr_a);
            free(arr_b);
            return 1;
        }
        memset(arr_a[i], 0, sizeof(*arr_a[i]));
        memset(arr_b[i], 0, sizeof(*arr_b[i]));

        arr_a[i]->dir = _strdup(buf);
        arr_b[i]->dir = _strdup(buf);
        arr_a[i]->dirlen = (int)strlen(buf);
        arr_b[i]->dirlen = (int)strlen(buf);
        arr_a[i]->plugin_list_index = rand() % 100;
        arr_b[i]->plugin_list_index = rand() % 100;
    }

    /* Use the same initial ordering for both implementations. */
    for (int i = 0; i < N; i++)
    {
        if (rand() % 2)
        {
            img_iterator_node tmp = *arr_a[i];
            *arr_a[i] = *arr_b[i];
            *arr_b[i] = tmp;
        }
    }

    /* Preserve initial pointer ordering of the array-based naive sort
     * for per-round restore (same rationale as perf_img_once). */
    memcpy(saved_b, arr_b, (size_t)N * sizeof(img_iterator_node *));

    /* ---- merge sort (subdir) ---- */
    {
        int reps;
        img_iterator_node *out_a;
        double t0;

        /* Calibrate on the same nodes, then measure. */
        t0 = perf_timestamp();
        for (int k = 0; k < 1; k++)
        {
            for (int i = 0; i < N; i++)
                arr_a[i]->next = (i < N - 1) ? arr_a[i + 1] : NULL;
            (void)perf_subdir_msort(arr_a[0], N);
        }
        reps = perf_pick_reps(perf_seconds_elapsed(t0, perf_timestamp()));

        t0 = perf_timestamp();
        for (int k = 0; k < reps; k++)
        {
            for (int i = 0; i < N; i++)
                arr_a[i]->next = (i < N - 1) ? arr_a[i + 1] : NULL;
            (void)perf_subdir_msort(arr_a[0], N);
        }
        *t_merge = perf_seconds_elapsed(t0, perf_timestamp()) / (double)reps;
        fprintf(stderr, "PERF-SUBDIR: N=%d merge reps=%d\n", N, reps);

        /* Untimed correctness check on the same nodes. */
        for (int i = 0; i < N; i++)
            arr_a[i]->next = (i < N - 1) ? arr_a[i + 1] : NULL;
        out_a = perf_subdir_msort(arr_a[0], N);
        {
            img_iterator_node *p = out_a;
            int ok = 1;
            while (p && p->next)
            {
                if (ventoy_cmp_subdir(p, p->next) > 0)
                { ok = 0; break; }
                p = p->next;
            }
            if (!ok)
            {
                fprintf(stderr, "PERF-SUBDIR: merge sort failed correctness for N=%d\n", N);
                failed = 1;
            }
        }

        /* Free subdir nodes. */
        while (out_a)
        {
            img_iterator_node *next = out_a->next;
            free((void *)out_a->dir);
            grub_free(out_a);
            out_a = next;
        }
    }

    /* ---- insertion sort (subdir) ---- */
    {
        int reps;
        img_iterator_node *out_b;
        double t0;

        t0 = perf_timestamp();
        for (int k = 0; k < 1; k++)
        {
            memcpy(arr_b, saved_b, (size_t)N * sizeof(img_iterator_node *));
            (void)naive_subdir_insertion_sort(arr_b, N);
        }
        reps = perf_pick_reps(perf_seconds_elapsed(t0, perf_timestamp()));

        t0 = perf_timestamp();
        for (int k = 0; k < reps; k++)
        {
            memcpy(arr_b, saved_b, (size_t)N * sizeof(img_iterator_node *));
            (void)naive_subdir_insertion_sort(arr_b, N);
        }
        *t_naive = perf_seconds_elapsed(t0, perf_timestamp()) / (double)reps;

        /* No-restore control for the subdir naive path (same rationale
         * as in perf_img_once). */
        {
            double t0c = perf_timestamp();
            for (int k = 0; k < reps; k++)
                memcpy(arr_b, saved_b, (size_t)N * sizeof(img_iterator_node *));
            double restore_share =
                100.0 * (perf_seconds_elapsed(t0c, perf_timestamp()) / (double)reps)
                        / (*t_naive > 0.0 ? *t_naive : 1e-9);
            fprintf(stderr, "PERF-SUBDIR: N=%d naive reps=%d restore_overhead=%.1f%%\n",
                    N, reps, restore_share);
        }

        memcpy(arr_b, saved_b, (size_t)N * sizeof(img_iterator_node *));
        out_b = naive_subdir_insertion_sort(arr_b, N);
        {
            img_iterator_node *p = out_b;
            int ok = 1;
            while (p && p->next)
            {
                if (ventoy_cmp_subdir(p, p->next) > 0)
                { ok = 0; break; }
                p = p->next;
            }
            if (!ok)
            {
                fprintf(stderr, "PERF-SUBDIR: insertion sort failed correctness for N=%d\n", N);
                failed = 1;
            }
        }

        while (out_b)
        {
            img_iterator_node *next = out_b->next;
            free((void *)out_b->dir);
            grub_free(out_b);
            out_b = next;
        }
    }

    free(saved_b);
    free(arr_a);
    free(arr_b);
    return failed;
}

static int perf_subdir_run(void)
{
    int failed = 0;
    int perf_test_subdir_sizes[] = { 32, 128, 512, 2048, 8192, 16384 };
    int perf_test_subdir_sizes_len =
        (int)(sizeof(perf_test_subdir_sizes) / sizeof(perf_test_subdir_sizes[0]));

    fprintf(stderr, "PERF-SUBDIR: running subdir sort comparison\n");

    for (int t = 0; t < perf_test_subdir_sizes_len; t++)
    {
        int N = perf_test_subdir_sizes[t];
        double t_merge = 0.0;
        double t_naive = 0.0;

        if (perf_subdir_once(N, &t_merge, &t_naive))
            failed = 1;
        printf("PERF-SUBDIR merge N=%d time=%.6f sec\n", N, t_merge);
        printf("PERF-SUBDIR naive N=%d time=%.6f sec\n", N, t_naive);
    }

    return failed;
}

/* Seed sweep for the subdir workload (mirrors perf_img_sweep). */
static int perf_subdir_sweep(int nseeds)
{
    int failed = 0;
    static const int perf_test_subdir_sizes[] = { 32, 128, 512, 2048, 8192, 16384 };
    const int perf_test_subdir_sizes_len =
        (int)(sizeof(perf_test_subdir_sizes) / sizeof(perf_test_subdir_sizes[0]));
    perf_stats *st_merge = (perf_stats *)calloc((size_t)perf_test_subdir_sizes_len,
                                                sizeof(perf_stats));
    perf_stats *st_naive = (perf_stats *)calloc((size_t)perf_test_subdir_sizes_len,
                                                sizeof(perf_stats));

    if (!st_merge || !st_naive)
    {
        fprintf(stderr, "PERF-SUBDIR: out of memory for sweep stats\n");
        free(st_merge);
        free(st_naive);
        return 1;
    }

    for (int s = 1; s <= nseeds; s++)
    {
        srand((unsigned int)s);
        for (int t = 0; t < perf_test_subdir_sizes_len; t++)
        {
            int N = perf_test_subdir_sizes[t];
            double t_merge = 0.0;
            double t_naive = 0.0;

            if (perf_subdir_once(N, &t_merge, &t_naive))
                failed = 1;
            perf_stats_add(&st_merge[t], t_merge);
            perf_stats_add(&st_naive[t], t_naive);
            fprintf(stderr, "SWEEP-SUBDIR seed=%d N=%d merge=%.6f naive=%.6f sec\n",
                    s, N, t_merge, t_naive);
        }
    }

    for (int t = 0; t < perf_test_subdir_sizes_len; t++)
    {
        int N = perf_test_subdir_sizes[t];
        printf("SWEEP-SUBDIR N=%d seeds=%d merge mean=%.9f min=%.9f max=%.9f | "
               "naive mean=%.9f min=%.9f max=%.9f sec\n",
               N, st_merge[t].runs,
               st_merge[t].sum / st_merge[t].runs,
               st_merge[t].min, st_merge[t].max,
               st_naive[t].sum / st_naive[t].runs,
               st_naive[t].min, st_naive[t].max);
    }

    free(st_merge);
    free(st_naive);
    return failed;
}
#endif /* VENTOY_SORT_TEST_PERF */

/* ------------------------------------------------------------------ */
/* Tests                                                               */
/* ------------------------------------------------------------------ */

static int test_cmp_img_case_sensitive(void)
{
    img_info a, b;
    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    copy_name(a.name, "Zulu.iso", sizeof(a.name));
    copy_name(b.name, "alpha.iso", sizeof(b.name));

    g_sort_case_sensitive = 1;
    g_plugin_image_list = 0;

    /* ASCII order: 'Z' (90) < 'a' (97), so "Zulu" sorts before "alpha". */
    int r = ventoy_cmp_img(&a, &b);
    if (r >= 0) {
        fprintf(stderr, "FAIL: case-sensitive ASCII order expected 'Zulu' < 'alpha'\n");
        return 1;
    }
    return 0;
}

static int test_cmp_img_case_insensitive(void)
{
    img_info a, b;
    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    copy_name(a.name, "Zulu.iso", sizeof(a.name));
    copy_name(b.name, "alpha.iso", sizeof(b.name));

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    /* Case-insensitive lexical order: "alpha" < "zulu", so "Zulu" > "alpha". */
    int r = ventoy_cmp_img(&a, &b);
    if (r <= 0) {
        fprintf(stderr, "FAIL: case-insensitive order expected 'Zulu' > 'alpha'\n");
        return 1;
    }
    return 0;
}

static int test_cmp_img_equal_names(void)
{
    img_info a, b;
    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    copy_name(a.name, "same.iso", sizeof(a.name));
    copy_name(b.name, "same.iso", sizeof(b.name));

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    int r = ventoy_cmp_img(&a, &b);
    if (r != 0) {
        fprintf(stderr, "FAIL: equal names should compare equal\n");
        return 1;
    }
    return 0;
}

static int test_cmp_img_prefix_equal_stability_tie(void)
{
    /* If names compare equal, the merge sort must not swap them out of
     * insertion order on the <= 0 path. This is the stability property. */
    img_info a, b;
    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    copy_name(a.name, "aaa.iso", sizeof(a.name));
    copy_name(b.name, "aaa.iso", sizeof(b.name));
    a.id = 1;
    b.id = 2;

    g_sort_case_sensitive = 1;
    g_plugin_image_list = 0;

    /* a before b initially */
    a.next = &b;
    b.prev = &a;
    b.next = NULL;

    /* Merge of [a] and [b] should keep a then b */
    img_info *out = ventoy_img_merge(&a, &b);
    if (!out || out != &a || a.next != &b) {
        fprintf(stderr, "FAIL: stable merge should keep equal elements in order\n");
        return 1;
    }
    return 0;
}

static int test_msort_empty(void)
{
    img_info *list = NULL;
    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    img_info *out = ventoy_img_msort(list, 0);
    if (out != NULL) {
        fprintf(stderr, "FAIL: empty list should remain empty\n");
        return 1;
    }
    return 0;
}

static int test_msort_single(void)
{
    img_info *item = make_item("one.iso", 1, 100);
    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    img_info *out = ventoy_img_msort(item, 1);
    if (out != item) {
        fprintf(stderr, "FAIL: single item should be returned unchanged\n");
        free_list(out);
        return 1;
    }
    free_list(out);
    return 0;
}

static int test_msort_reverse_order(void)
{
    img_info *items[4];
    int i;

    for (i = 0; i < 4; i++)
        items[i] = make_item("", i, 0);

    copy_name(items[0]->name, "d.iso", sizeof(items[0]->name));
    copy_name(items[1]->name, "c.iso", sizeof(items[1]->name));
    copy_name(items[2]->name, "b.iso", sizeof(items[2]->name));
    copy_name(items[3]->name, "a.iso", sizeof(items[3]->name));

    items[0]->next = items[1];
    items[1]->prev = items[0];
    items[1]->next = items[2];
    items[2]->prev = items[1];
    items[2]->next = items[3];
    items[3]->prev = items[2];
    items[3]->next = NULL;

    g_sort_case_sensitive = 1;
    g_plugin_image_list = 0;

    img_info *out = ventoy_img_msort(items[0], 4);

    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: reversed list should become ordered with valid prev\n");
        free_list(out);
        return 1;
    }
    free_list(out);
    return 0;
}

static int test_msort_duplicate_names_stable(void)
{
    img_info *items[3];
    int i;

    for (i = 0; i < 3; i++)
        items[i] = make_item("", i, 0);

    copy_name(items[0]->name, "dup.iso", sizeof(items[0]->name));
    copy_name(items[1]->name, "dup.iso", sizeof(items[1]->name));
    copy_name(items[2]->name, "dup.iso", sizeof(items[2]->name));
    items[0]->id = 10;
    items[1]->id = 20;
    items[2]->id = 30;

    items[0]->next = items[1];
    items[1]->prev = items[0];
    items[1]->next = items[2];
    items[2]->prev = items[1];
    items[2]->next = NULL;

    g_sort_case_sensitive = 1;
    g_plugin_image_list = 0;

    img_info *out = ventoy_img_msort(items[0], 3);
    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: duplicated name list should stay ordered and linked\n");
        free_list(out);
        return 1;
    }

    /* Stability: equal keys should preserve original relative order. */
    {
        char last_name[256] = {0};
        int last_id_for_name = -1;
        int ok = 1;
        for (img_info *p = out; p; p = p->next) {
            if (strcmp(p->name, last_name) == 0) {
                if (p->id < last_id_for_name) {
                    ok = 0;
                    break;
                }
            } else {
                copy_name(last_name, p->name, sizeof(last_name));
                last_id_for_name = p->id;
            }
        }
        if (!ok) {
            fprintf(stderr, "FAIL: stability broken for duplicate keys\n");
            free_list(out);
            return 1;
        }
    }
    free_list(out);
    return 0;
}

static int test_msort_large_random(void)
{
    const int N = 4096;
    img_info **items = (img_info **)malloc(N * sizeof(img_info *));
    if (!items) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    for (int i = 0; i < N; i++) {
        char name[64];
        snprintf(name, sizeof(name), "%05u.iso", rand() % 20000);
        items[i] = make_item(name, i, (grub_uint64_t)rand());
    }

    for (int i = 0; i < N - 1; i++) {
        items[i]->next = items[i + 1];
        items[i + 1]->prev = items[i];
    }

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    clock_t start = clock();
    img_info *out = ventoy_img_msort(items[0], N);
    clock_t end = clock();
    double elapsed = (double)(end - start) / (double)CLOCKS_PER_SEC;

    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: random list should be sorted and linked\n");
        free_list(out);
        free(items);
        return 1;
    }

    /* Stability: for equal names, ids must rise. */
    {
        char last_name[256] = {0};
        int last_id_for_name = -1;
        int ok = 1;
        for (img_info *p = out; p; p = p->next) {
            if (strcmp(p->name, last_name) == 0) {
                if (p->id < last_id_for_name) {
                    ok = 0;
                    break;
                }
            } else {
                copy_name(last_name, p->name, sizeof(last_name));
                last_id_for_name = p->id;
            }
        }
        if (!ok) {
            fprintf(stderr, "FAIL: stability broken for large random list\n");
            free_list(out);
            free(items);
            return 1;
        }
    }

    printf("OK large random sort (%d items, %.6f sec)\n", N, elapsed);

    free_list(out);
    free(items);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Production-parity mirrors                                            */
/*                                                                      */
/* ventoy_img_merge/ventoy_img_msort above mirror the sort ALGORITHM    */
/* from ventoy_cmd.c; the two functions below additionally mirror the   */
/* production merge's in-place link structure and msort's early-return  */
/* shape so that if production and shim ever drift structurally, the    */
/* parity regression below has a second implementation to catch it.     */
/* Keep these byte-equivalent in structure to GRUB2/MOD_SRC/grub-2.04/  */
/* grub-core/ventoy/ventoy_cmd.c.                                       */
/* ------------------------------------------------------------------ */

static img_info *prod_img_merge(img_info *a, img_info *b)
{
    img_info head;
    img_info *tail = &head;
    long steps = 0;

    head.next = NULL;
    head.prev = NULL;

    while (a && b)
    {
        if (ventoy_cmp_img(a, b) <= 0)
        {
            tail->next = a;
            a->prev = tail;
            a = a->next;
        }
        else
        {
            tail->next = b;
            b->prev = tail;
            b = b->next;
        }
        tail = tail->next;

        /* Harness-only safety valve (the ONE intentional deviation
         * from production): if the mirror is ever mutated back into
         * the aliasing boot-hang bug, the loop never terminates and
         * would hang the whole suite. Convert that hang into a clean
         * failure instead. 1e7 steps is ~100x any legitimate merge. */
        if (++steps > 10000000L)
        {
            fprintf(stderr,
                    "FAIL: prod_img_merge exceeded step limit "
                    "(aliasing/cycle bug reintroduced?)\n");
            exit(3);
        }
    }

    if (a)
    {
        tail->next = a;
        a->prev = tail;
    }
    else if (b)
    {
        tail->next = b;
        b->prev = tail;
    }

    if (head.next)
    {
        head.next->prev = NULL;
    }

    return head.next;
}

static img_info *prod_img_msort(img_info *list, int n)
{
    img_info *a;
    img_info *b;

    if (n <= 1)
    {
        return list;
    }

    a = list;
    b = list;
    {
        int k = n / 2;
        while (k-- && b)
        {
            b = b->next;
        }
    }

    if (b)
    {
        /* Terminate the first half so the two recursive calls operate
         * on disjoint lists (the boot-hang bug: without the sever,
         * the merge re-consumes a's tail nodes and never returns). */
        img_info *prev_a = list;
        while (prev_a->next != b && prev_a->next)
        {
            prev_a = prev_a->next;
        }
        if (prev_a->next == b)
        {
            prev_a->next = NULL;
        }

        a = prod_img_msort(a, n / 2);
        b = prod_img_msort(b, n - n / 2);
        return prod_img_merge(a, b);
    }

    return list;
}

static int test_prod_msort_parity(void)
{
    /* Production-parity regression, promoted from _prod_msort_check.c
     * (the scratch driver that caught the boot-hang bug in
     * ventoy_cmd.c before it shipped). Runs the production-structured
     * mirrors over n = 1..64 with deterministic names, replicating
     * ventoy_cmd_list_img's post-sort one-pass prev rebuild, and
     * requires: node count preserved (cycle guard), ordering, prev
     * links valid, and stability on a duplicate-heavy list. */
    int failed = 0;
    int n, i;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    for (n = 1; n <= 64; n++)
    {
        img_info **items = (img_info **)malloc((size_t)n * sizeof(img_info *));
        img_info *head;
        if (!items) {
            fprintf(stderr, "out of memory\n");
            exit(2);
        }
        for (i = 0; i < n; i++) {
            char name[64];
            snprintf(name, sizeof(name), "%05u.iso",
                     (unsigned)((i * 2654435761u) % 99991u));
            items[i] = make_item(name, i, 0);
        }
        for (i = 0; i < n - 1; i++) {
            items[i]->next = items[i + 1];
            items[i + 1]->prev = items[i];
        }

        head = prod_img_msort(items[0], n);

        /* Cycle guard FIRST and capped: the aliasing bug (removed
         * sever) produces a cyclic tail, and the uncapped walkers
         * below (list_is_ordered, list_prev_pointers_valid, free_list)
         * would hang on it before reporting anything. If the count
         * walk does not land on exactly n nodes, bail out without
         * touching the (possibly cyclic) list further. */
        {
            int count = 0;
            img_info *p;
            for (p = head; p; p = p->next) {
                count++;
                if (count > n) {
                    fprintf(stderr, "FAIL: prod-parity n=%d next-chain exceeds n "
                                    "(cycle — aliasing bug reintroduced?)\n", n);
                    return 1;  /* cyclic: do NOT walk or free it */
                }
            }
            if (count != n) {
                fprintf(stderr, "FAIL: prod-parity n=%d produced %d nodes\n", n, count);
                return 1;
            }
        }

        /* Post-sort prev rebuild, exactly as ventoy_cmd_list_img does.
         * Safe now: the list is proven acyclic with exactly n nodes. */
        {
            img_info *cur;
            for (cur = head; cur && cur->next; cur = cur->next)
                cur->next->prev = cur;
        }

        if (!list_is_ordered(head) || !list_prev_pointers_valid(head)) {
            fprintf(stderr, "FAIL: prod-parity n=%d not ordered/linked\n", n);
            failed = 1;
        }

        free_list(head);
        free(items);
    }

    /* Duplicate-heavy stability check through the production mirrors. */
    {
        img_info *dups[6];
        int ok = 1;
        for (i = 0; i < 6; i++)
            dups[i] = make_item("dup.iso", i, 0);
        for (i = 0; i < 5; i++) {
            dups[i]->next = dups[i + 1];
            dups[i + 1]->prev = dups[i];
        }
        {
            img_info *head = prod_img_msort(dups[0], 6);
            img_info *p;
            int last_id = -1;
            for (p = head; p; p = p->next) {
                if (p->id <= last_id)
                    ok = 0;
                last_id = p->id;
            }
            free_list(head);
        }
        if (!ok) {
            fprintf(stderr, "FAIL: prod-parity duplicate list not stable/ordered\n");
            failed = 1;
        }
    }

    /* Count-mismatch tolerance: production guards g_ventoy_img_count
     * against the walked length before calling msort, but the guard is
     * printf-and-continue — so msort itself must stay memory-safe and
     * terminate when n is wrong. n > actual length would walk past the
     * tail (NULL deref inside the split loop / recursion); n < actual
     * length leaves a tail beyond the split point, and the merge's
     * remaining-run append must keep the whole list reachable and
     * linkable. Verify both directions terminate with intact linkage. */
    {
        img_info *items[8];
        int sizes[] = { 8, 8, 8, 8 };
        int ns[]    = { 9, 12, 6, 4 };   /* claimed n: over, way over, under, half */
        int case_i;

        for (case_i = 0; case_i < 4; case_i++) {
            img_info *head;
            int walked = 0;
            img_info *p;

            for (i = 0; i < sizes[case_i]; i++) {
                char name[64];
                snprintf(name, sizeof(name), "%05u.iso",
                         (unsigned)((i * 40503u) % 99991u));
                items[i] = make_item(name, i, 0);
            }
            for (i = 0; i < sizes[case_i] - 1; i++) {
                items[i]->next = items[i + 1];
                items[i + 1]->prev = items[i];
            }

            head = prod_img_msort(items[0], ns[case_i]);

            /* The call must terminate and return a traversable list; no
             * count assertion here (mismatch is the caller's guard's
             * job), only memory-safety of the walk. */
            for (p = head; p; p = p->next) {
                walked++;
                if (walked > sizes[case_i] + 8) {
                    fprintf(stderr, "FAIL: prod-parity mismatch n=%d on %d nodes: "
                                    "walk exceeded list (cycle)\n",
                                    ns[case_i], sizes[case_i]);
                    failed = 1;
                    break;
                }
            }
            if (walked > sizes[case_i] && failed) {
                /* cyclic: do not free via next-chain */
                continue;
            }

            /* Linkage must remain a single acyclic chain, whatever the
             * claimed n did to the ordering. */
            if (walked != sizes[case_i]) {
                fprintf(stderr, "FAIL: prod-parity mismatch n=%d on %d nodes: "
                                "only %d nodes reachable\n",
                                ns[case_i], sizes[case_i], walked);
                failed = 1;
            }

            free_list(head);
        }
    }

    return failed;
}

static void build_long_name(char *buf, size_t bufsz, const char *tag)
{
    /* Fill with a repeating filler so any short/long mix-up in the
     * copy path is visible in the compared bytes, then tag the tail. */
    size_t i;
    size_t taglen = strlen(tag);
    for (i = 0; i + 1 < bufsz; i++)
        buf[i] = (char)('a' + (int)(i % 26));
    buf[i] = '\0';
    if (taglen <= i)
        memcpy(buf + i - taglen, tag, taglen);
}

static int test_make_item_long_name_copies_and_truncates(void)
{
    /* img_info.name is char[256] (255 chars + NUL). The common call
     * sites build names in 64-byte buffers, so nothing else exercises
     * names at or beyond that boundary. This pins make_item()'s copy
     * contract for long names:
     *   - a 64-char name (the historical buffer size) fits exactly
     *   - a >64-char name is copied in full
     *   - anything longer than 255 chars is truncated to 255 chars
     *     with a terminating NUL (no overflow, no unterminated name) */
    char name300[300];
    char name65[sizeof(((img_info *)0)->name)];  /* 256 => 255 chars max */
    char name64[64];
    img_info *item = NULL;
    size_t i;

    build_long_name(name64, sizeof(name64), "");            /* exactly 63 chars */
    build_long_name(name65, sizeof(name65), "");            /* exactly 255 chars */
    build_long_name(name300, sizeof(name300), "TAIL");      /* 299 chars */

    item = make_item(name64, 1, 0);
    if (strlen(item->name) != strlen(name64) ||
        memcmp(item->name, name64, strlen(name64)) != 0) {
        fprintf(stderr, "FAIL: 64-byte-buffer name must be copied byte-exact\n");
        free_list(item);
        return 1;
    }
    free_list(item);

    item = make_item(name65, 2, 0);
    if (strlen(item->name) != 255 ||
        memcmp(item->name, name65, 255) != 0) {
        fprintf(stderr, "FAIL: 255-char name must fit img_info.name in full\n");
        free_list(item);
        return 1;
    }
    free_list(item);

    item = make_item(name300, 3, 0);
    if (strlen(item->name) != 255) {
        fprintf(stderr, "FAIL: 299-char name must truncate to 255 chars\n");
        free_list(item);
        return 1;
    }
    for (i = 0; i < 255; i++) {
        if (item->name[i] != name300[i]) {
            fprintf(stderr, "FAIL: truncation must keep the first 255 bytes intact\n");
            free_list(item);
            return 1;
        }
    }
    free_list(item);
    return 0;
}

static int test_cmp_img_long_names_differing_after_byte64(void)
{
    /* Two names identical for their first 100 bytes but differing at
     * byte 100 must NOT compare equal: the comparator walks the full
     * name, not just the first 64 bytes. A regression that truncated
     * comparisons at the historical 64-byte buffer size would make
     * these equal and break ordering for long ISO names. */
    char n1[300], n2[300];
    img_info *a, *b;
    int r_cs, r_ci;

    build_long_name(n1, sizeof(n1), "");
    memcpy(n2, n1, sizeof(n2));
    n2[100] = (char)(n1[100] + 1);   /* single differing byte deep in the name */

    a = make_item(n1, 1, 0);
    b = make_item(n2, 2, 0);

    g_sort_case_sensitive = 1;
    g_plugin_image_list = 0;
    r_cs = ventoy_cmp_img(a, b);

    g_sort_case_sensitive = 0;
    r_ci = ventoy_cmp_img(a, b);

    if (r_cs >= 0) {
        fprintf(stderr, "FAIL: names differing at byte 100 must order (case-sensitive)\n");
        free_list(a); free_list(b);
        return 1;
    }
    if (r_ci >= 0) {
        fprintf(stderr, "FAIL: names differing at byte 100 must order (case-insensitive)\n");
        free_list(a); free_list(b);
        return 1;
    }

    free_list(a);
    free_list(b);
    return 0;
}

static int test_msort_long_names_stable_and_ordered(void)
{
    /* End-to-end: sort a list of long (>64-byte) names, including a
     * duplicated 200-char name, and require ordered output, valid prev
     * links, and insertion-order stability within the equal-key group. */
    const int N = 32;
    img_info **items = (img_info **)malloc(N * sizeof(img_info *));
    char longdup[256];
    img_info *out = NULL;
    img_info *dup_first = NULL;
    int i, ok;

    if (!items) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }

    build_long_name(longdup, sizeof(longdup), "");  /* exactly 255 chars */

    for (i = 0; i < N; i++) {
        if (i == 4 || i == 17) {
            items[i] = make_item(longdup, i, 0);     /* duplicate long key */
            if (i == 4)
                dup_first = items[i];
        } else {
            char name[128];
            build_long_name(name, sizeof(name), "");
            name[0] = (char)('A' + (i % 26));        /* vary first byte for spread */
            snprintf(name + 120, sizeof(name) - 120, "%03d.iso", i);
            items[i] = make_item(name, i, 0);
        }
    }

    for (i = 0; i < N - 1; i++) {
        items[i]->next = items[i + 1];
        items[i + 1]->prev = items[i];
    }

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    out = ventoy_img_msort(items[0], N);
    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: long-name list must sort ordered with valid links\n");
        free_list(out);
        free(items);
        return 1;
    }

    /* Stability: the two duplicates must stay in insertion order 4, 17. */
    {
        img_info *p;
        int seen_first = 0;
        ok = 0;
        for (p = out; p; p = p->next) {
            if (p == dup_first)
                seen_first = 1;
            else if (p->id == 17 && strcmp(p->name, longdup) == 0) {
                if (!seen_first) {
                    fprintf(stderr, "FAIL: duplicate long names must keep insertion order\n");
                    free_list(out);
                    free(items);
                    return 1;
                }
                ok = 1;
                break;
            }
        }
        if (!ok) {
            fprintf(stderr, "FAIL: duplicate long-name pair not found in output\n");
            free_list(out);
            free(items);
            return 1;
        }
    }

    free_list(out);
    free(items);
    return 0;
}

static int test_swap_preserves_neighbors(void)
{
    img_info *a = make_item("a.iso", 1, 10);
    img_info *b = make_item("b.iso", 2, 20);
    img_info *c = make_item("c.iso", 3, 30);

    a->next = b;
    b->prev = a;
    b->next = c;
    c->prev = b;
    c->next = NULL;

    ventoy_swap_img(a, c);

    if (a->id != 3 || b->id != 2 || c->id != 1) {
        fprintf(stderr, "FAIL: swap should exchange contents\n");
        free_list(a);
        return 1;
    }

    /* Linked structure should still form a single list a<->b<->c. */
    if (a->next != b || b->next != c || c->prev != b || b->prev != a) {
        fprintf(stderr, "FAIL: swap should preserve surrounding links\n");
        free_list(a);
        return 1;
    }
    if (a->prev != NULL || c->next != NULL) {
        fprintf(stderr, "FAIL: swap should preserve endpoints\n");
        free_list(a);
        return 1;
    }

    free_list(a);
    return 0;
}

static int test_plugin_list_index_mode(void)
{
    img_info a, b;
    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    copy_name(a.name, "zzz.iso", sizeof(a.name));
    copy_name(b.name, "aaa.iso", sizeof(b.name));

    g_sort_case_sensitive = 0;
    g_plugin_image_list = VENTOY_IMG_WHITE_LIST;
    a.plugin_list_index = 2;
    b.plugin_list_index = 1;

    /* In plugin list mode, comparison should be by plugin_list_index only. */
    int r = ventoy_cmp_img(&a, &b);
    if (r <= 0) {
        fprintf(stderr, "FAIL: plugin list mode should sort by plugin_list_index\n");
        return 1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* ventoy_cmp_subdir regression cases                                  */
/* ------------------------------------------------------------------ */

static int test_cmp_subdir_parent_before_child(void)
{
    /* In the real tree walk, ventoy_cmp_subdir() is only called on
     * sibling nodes (same parent), so the shortest meaningful path is
     * a top-level dir like "/boot/" (dirlen=6 including trailing slash).
     *
     * dirlen is the return value of grub_snprintf(..., "%s%s/", ...)
     * which does NOT include the null terminator. So:
     *   "/boot/" -> dirlen=6
     *   "/boot/grub/" -> dirlen=11
     */
    img_iterator_node a, b;

    a.dir = "/boot/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 0;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 0;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    int r = ventoy_cmp_subdir(&a, &b);
    if (r >= 0) {
        fprintf(stderr, "FAIL: /boot/ should sort before /boot/grub/\n");
        return 1;
    }
    return 0;
}

static int test_cmp_subdir_deep_child_last(void)
{
    /* Sibling ordering in the tree walk: shallower paths (fewer
     * subpath components) sort before deeper descendants that share
     * the same prefix, e.g. /boot/ before /boot/grub/. */
    img_iterator_node a, b, c;

    a.dir = "/boot/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 0;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 0;

    c.dir = "/boot/grub/menu/";
    c.dirlen = (int)strlen(c.dir);
    c.plugin_list_index = 0;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    if (ventoy_cmp_subdir(&a, &b) >= 0 ||
        ventoy_cmp_subdir(&b, &c) >= 0 ||
        ventoy_cmp_subdir(&a, &c) >= 0) {
        fprintf(stderr, "FAIL: /boot/ < /boot/grub/ < /boot/grub/menu/\n");
        return 1;
    }
    return 0;
}

static int test_cmp_subdir_equal_dirs(void)
{
    img_iterator_node a, b;

    a.dir = "/boot/grub/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 0;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 0;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    int r = ventoy_cmp_subdir(&a, &b);
    if (r != 0) {
        fprintf(stderr, "FAIL: identical dirs should compare equal\n");
        return 1;
    }
    return 0;
}

static int test_cmp_subdir_case_insensitive(void)
{
    img_iterator_node a, b;

    a.dir = "/Boot/GRUB/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 0;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 0;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    int r = ventoy_cmp_subdir(&a, &b);
    if (r != 0) {
        fprintf(stderr, "FAIL: /Boot/GRUB and /boot/grub should compare equal\n");
        return 1;
    }
    return 0;
}

static int test_cmp_subdir_case_sensitive(void)
{
    img_iterator_node a, b;

    a.dir = "/Boot/GRUB/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 0;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 0;

    g_sort_case_sensitive = 1;
    g_plugin_image_list = 0;

    /* ASCII: 'B' (66) < 'b' (98), 'G' (71) < 'g' (103). */
    int r = ventoy_cmp_subdir(&a, &b);
    if (r >= 0) {
        fprintf(stderr, "FAIL: /Boot/GRUB should sort before /boot/grub case-sensitively\n");
        return 1;
    }
    return 0;
}

static int test_cmp_subdir_plugin_list_mode(void)
{
    img_iterator_node a, b;

    a.dir = "/zzz deeply nested path/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 2;

    b.dir = "/aaa/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 1;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = VENTOY_IMG_WHITE_LIST;

    /* In plugin-list mode, dir contents are ignored completely. */
    int r = ventoy_cmp_subdir(&a, &b);
    if (r <= 0) {
        fprintf(stderr, "FAIL: plugin list mode should sort by plugin_list_index\n");
        return 1;
    }
    return 0;
}

static int test_cmp_subdir_empty_dir_vs_nonempty(void)
{
    /* Corner case: one node has a zero-length dir (dirlen == 0).
     * len = min(0, k) == 0, so the loop bound (i < len - 1) is -1 and
     * the loop body must never execute: no byte of either path may be
     * dereferenced (dir may point at "" whose only byte is the NUL,
     * or be otherwise unreadable beyond that). Both c1 and c2 must
     * stay 0, so an empty dir compares EQUAL to any non-empty dir.
     *
     * This pins two things at once:
     *   1. safety — a naive rewrite of the bound as unsigned math
     *      (len - 1 on a size_t) would wrap to SIZE_MAX and read
     *      out of bounds; this test would crash under such a change
     *   2. contract — the comparator is a pure function of (dir, dirlen)
     *      and must not depend on bytes past the recorded length */
    const char *empty = "";
    img_iterator_node a, b;

    a.dir = empty;
    a.dirlen = 0;
    a.plugin_list_index = 0;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 0;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    if (ventoy_cmp_subdir(&a, &b) != 0) {
        fprintf(stderr, "FAIL: empty dir vs non-empty dir must compare equal (dirlen=0 skips the byte loop)\n");
        return 1;
    }
    if (ventoy_cmp_subdir(&b, &a) != 0) {
        fprintf(stderr, "FAIL: non-empty dir vs empty dir must compare equal (symmetric case)\n");
        return 1;
    }
    /* Both empty must also be a clean equal. */
    {
        img_iterator_node e;
        e.dir = empty;
        e.dirlen = 0;
        e.plugin_list_index = 0;
        if (ventoy_cmp_subdir(&a, &e) != 0) {
            fprintf(stderr, "FAIL: empty dir vs empty dir must compare equal\n");
            return 1;
        }
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* ventoy_cmp_subdir stability regression                              */
/* ------------------------------------------------------------------ */

#if VENTOY_SORT_TEST_PERF
static int test_cmp_subdir_equal_dirs_preserve_insertion_order(void)
{
    /* Two subdir nodes with equal dir/dirlen but different
     * plugin_list_index must compare equal (dir contents are equal),
     * and the stable merge sort (perf_subdir_merge) must preserve their
     * insertion order on the <= 0 path. This exercises the stability
     * contract of ventoy_cmp_subdir() + perf_subdir_merge() when the
     * dir compare returns 0 but plugin_list_index differs. */
    img_iterator_node a, b;

    a.dir = "/boot/grub/";
    a.dirlen = (int)strlen(a.dir);
    a.plugin_list_index = 1;

    b.dir = "/boot/grub/";
    b.dirlen = (int)strlen(b.dir);
    b.plugin_list_index = 2;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    /* a and b are disjoint single-element lists (only next pointer;
     * img_iterator_node has no prev member in this shim) */
    a.next = NULL;
    b.next = NULL;

    /* ventoy_cmp_subdir should return 0 for equal dirs */
    int r = ventoy_cmp_subdir(&a, &b);
    if (r != 0) {
        fprintf(stderr, "FAIL: equal dirs should compare equal in non-plugin mode\n");
        return 1;
    }

    /* perf_subdir_merge should keep a then b (stable on <= 0) */
    img_iterator_node *out = perf_subdir_merge(&a, &b);
    if (!out || out != &a || a.next != &b) {
        fprintf(stderr, "FAIL: stable subdir merge should keep equal elements in order\n");
        return 1;
    }
    if (b.next != NULL) {
        fprintf(stderr, "FAIL: merged subdir list should end at b\n");
        return 1;
    }

    return 0;
}

static int test_cmp_subdir_equal_dirs_msort_preserves_order(void)
{
    /* Full msort regression: build a list of img_iterator_node items
     * with equal dir/dirlen pairs, sort with perf_subdir_msort, and
     * verify that insertion order is preserved within each equal-dir
     * group (stability of the subdir merge sort). */
    img_iterator_node a0, a1, b0, b1;

    a0.dir = "/alpha/";
    a0.dirlen = (int)strlen(a0.dir);
    a0.plugin_list_index = 10;

    a1.dir = "/alpha/";
    a1.dirlen = (int)strlen(a1.dir);
    a1.plugin_list_index = 20;

    b0.dir = "/beta/";
    b0.dirlen = (int)strlen(b0.dir);
    b0.plugin_list_index = 30;

    b1.dir = "/beta/";
    b1.dirlen = (int)strlen(b1.dir);
    b1.plugin_list_index = 40;

    /* Insertion order: a0, a1, b0, b1 as a single linked list (only
     * next pointers). This is a disjoint list passed to msort. */
    a0.next = &a1;
    a1.next = &b0;
    b0.next = &b1;
    b1.next = NULL;

    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

    /* Sort the whole list; equal-dir pairs should stay in insertion order */
    img_iterator_node *out = perf_subdir_msort(&a0, 4);

    /* Verify the result is a single ordered list with valid next pointers */
    {
        img_iterator_node *p = out;
        int count = 0;
        while (p) {
            if (p->next && ventoy_cmp_subdir(p, p->next) > 0) {
                fprintf(stderr, "FAIL: subdir msort result not ordered\n");
                return 1;
            }
            count++;
            p = p->next;
        }
        if (count != 4) {
            fprintf(stderr, "FAIL: subdir msort should produce 4-element list\n");
            return 1;
        }
    }

    /* After sorting by dir: /alpha/ pair first (a0, a1 in insertion order),
     * then /beta/ pair (b0, b1 in insertion order). */
    {
        img_iterator_node *p = out;

        if (p != &a0) {
            fprintf(stderr, "FAIL: first element should be a0 after stable subdir sort\n");
            return 1;
        }
        p = p->next;
        if (p != &a1) {
            fprintf(stderr, "FAIL: second element should be a1 (stability within /alpha/ pair)\n");
            return 1;
        }
        p = p->next;
        if (p != &b0) {
            fprintf(stderr, "FAIL: third element should be b0\n");
            return 1;
        }
        p = p->next;
        if (p != &b1) {
            fprintf(stderr, "FAIL: fourth element should be b1 (stability within /beta/ pair)\n");
            return 1;
        }
        if (p->next != NULL) {
            fprintf(stderr, "FAIL: list should end after b1\n");
            return 1;
        }
    }

    /* Note: out->dir points to string literals, not heap memory,
     * so we must NOT free them. Just free the stack-allocated structs
     * (which are actually locals, so no free needed — but be safe). */
    (void)out;
    return 0;
}
#endif /* VENTOY_SORT_TEST_PERF */

/* ------------------------------------------------------------------ */
/* g_sort_case_sensitive toggle mid-run regression                     */
/* ------------------------------------------------------------------ */

static int test_toggle_case_sensitive_does_not_corrupt_order(void)
{
    /* The sort order must be determined by the comparator state at the
     * moment each comparison happens. Flipping g_sort_case_sensitive
     * mid-sort should still yield a self-consistent total order under
     * the comparator active at comparison time, without crashing or
     * producing a cycle. This is a sanity check for callers that re-run
     * the sort after toggling the flag (menu-build perf investigation). */
    const int N = 64;
    img_info **items = (img_info **)malloc(N * sizeof(img_info *));
    if (!items) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }

    for (int i = 0; i < N; i++) {
        char name[64];
        snprintf(name, sizeof(name), "%05u.iso", (unsigned int)(rand() % 50000));
        items[i] = make_item(name, i, (grub_uint64_t)rand());
    }

    /* Build the initial list once; each phase reuses the same items. */
    for (int i = 0; i < N - 1; i++) {
        items[i]->next = items[i + 1];
        items[i + 1]->prev = items[i];
    }

    /* Phase 1: sort case-insensitively. */
    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;
    img_info *out = ventoy_img_msort(items[0], N);
    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: phase 1 (case-insensitive) sort must be valid\n");
        free_list(out);
        free(items);
        return 1;
    }
    /* Each element must compare non-negatively with its successor under
     * the case-insensitive comparator. */
    {
        int ok = 1;
        for (img_info *p = out; p && p->next; p = p->next) {
            if (ventoy_cmp_img(p, p->next) > 0) {
                ok = 0;
                break;
            }
        }
        if (!ok) {
            fprintf(stderr, "FAIL: phase 1 result not consistent with comparator\n");
            free_list(out);
            free(items);
            return 1;
        }
    }
    /* Do NOT free_list(out) here — out is the same nodes as items[],
     * and we need them alive for the next phases. */
    items[0]->prev = NULL;
    for (int i = 0; i < N - 1; i++) {
        items[i]->next = items[i + 1];
        items[i + 1]->prev = items[i];
    }
    items[N - 1]->next = NULL;

    /* Phase 2: sort case-sensitively from the same initial ordering. */
    g_sort_case_sensitive = 1;
    out = ventoy_img_msort(items[0], N);
    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: phase 2 (case-sensitive) sort must be valid\n");
        free_list(out);
        free(items);
        return 1;
    }
    {
        int ok = 1;
        for (img_info *p = out; p && p->next; p = p->next) {
            if (ventoy_cmp_img(p, p->next) > 0) {
                ok = 0;
                break;
            }
        }
        if (!ok) {
            fprintf(stderr, "FAIL: phase 2 result not consistent with comparator\n");
            free_list(out);
            free(items);
            return 1;
        }
    }
    /* Rebuild initial ordering for phase 3. */
    items[0]->prev = NULL;
    for (int i = 0; i < N - 1; i++) {
        items[i]->next = items[i + 1];
        items[i + 1]->prev = items[i];
    }
    items[N - 1]->next = NULL;

    /* Phase 3: sort case-insensitively again, to verify no state
     * corruption accumulated across the two prior phases. */
    g_sort_case_sensitive = 0;
    out = ventoy_img_msort(items[0], N);
    if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
        fprintf(stderr, "FAIL: phase 3 (case-insensitive) sort must be valid\n");
        free_list(out);
        free(items);
        return 1;
    }
    {
        int ok = 1;
        for (img_info *p = out; p && p->next; p = p->next) {
            if (ventoy_cmp_img(p, p->next) > 0) {
                ok = 0;
                break;
            }
        }
        if (!ok) {
            fprintf(stderr, "FAIL: phase 3 result not consistent with comparator\n");
            free_list(out);
            free(items);
            return 1;
        }
    }

    free_list(out);
    free(items);
    return 0;
}

static int test_toggle_case_sensitive_stress_multi_phase(void)
{
    /* Stress variant: toggle g_sort_case_sensitive many times mid-run
     * (N phases, each re-sorting the same items from the same initial
     * ordering). This verifies that no state corruption accumulates
     * across many toggles, which is the menu-build perf investigation
     * scenario where the sort may be re-run after each flag flip. */
    const int N = 64;
    const int PHASES = 8;
    img_info **items = (img_info **)malloc(N * sizeof(img_info *));
    if (!items) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }

    for (int i = 0; i < N; i++) {
        char name[64];
        snprintf(name, sizeof(name), "%05u.iso", (unsigned int)(rand() % 50000));
        items[i] = make_item(name, i, (grub_uint64_t)rand());
    }

    /* Build the initial list once. */
    items[0]->prev = NULL;
    for (int i = 0; i < N - 1; i++) {
        items[i]->next = items[i + 1];
        items[i + 1]->prev = items[i];
    }
    items[N - 1]->next = NULL;

    /* Run PHASES alternating between case-insensitive (0) and
     * case-sensitive (1). Each phase re-sorts from the same initial
     * ordering and verifies internal consistency.
     *
     * NOTE: the nodes must stay alive across phases — out always refers
     * to the same N nodes, just relinked. Free only once at the end. */
    img_info *out = NULL;
    for (int ph = 0; ph < PHASES; ph++) {
        g_sort_case_sensitive = (ph % 2 == 0) ? 0 : 1;
        g_plugin_image_list = 0;

        /* Rebuild the initial ordering before each sort. */
        items[0]->prev = NULL;
        for (int i = 0; i < N - 1; i++) {
            items[i]->next = items[i + 1];
            items[i + 1]->prev = items[i];
        }
        items[N - 1]->next = NULL;

        img_info *out = ventoy_img_msort(items[0], N);
        if (!list_is_ordered(out) || !list_prev_pointers_valid(out)) {
            fprintf(stderr, "FAIL: stress phase %d sort must be valid\n", ph);
            free_list(out);
            free(items);
            return 1;
        }

        /* Verify the result is consistent with the active comparator. */
        {
            int ok = 1;
            for (img_info *p = out; p && p->next; p = p->next) {
                if (ventoy_cmp_img(p, p->next) > 0) {
                    ok = 0;
                    break;
                }
            }
            if (!ok) {
                fprintf(stderr, "FAIL: stress phase %d result not consistent with comparator\n", ph);
                free_list(out);
                free(items);
                return 1;
            }
        }

        /* Stability: for equal names, ids must rise (preserved across
         * every phase regardless of comparator). */
        {
            char last_name[256] = {0};
            int last_id_for_name = -1;
            int ok = 1;
            for (img_info *p = out; p; p = p->next) {
                if (strcmp(p->name, last_name) == 0) {
                    if (p->id < last_id_for_name) {
                        ok = 0;
                        break;
                    }
                } else {
                    copy_name(last_name, p->name, sizeof(last_name));
                    last_id_for_name = p->id;
                }
            }
            if (!ok) {
                fprintf(stderr, "FAIL: stability broken at stress phase %d\n", ph);
                free_list(out);
                free(items);
                return 1;
            }
        }
    }

    /* Free the nodes once, after the final phase. */
    free_list(out);
    free(items);
    return 0;
}

int main(int argc, char **argv)
{
    int failed = 0;
    unsigned int seed = 1;  /* historical default: fully deterministic run */
    int sweep_seeds = 0;    /* 0 = sweep disabled */

    /* Optional: --seed <n> varies the rand() stream feeding the perf
     * workloads and the randomized test data, for variance studies.
     * The default keeps byte-identical data across runs.
     * --sweep <n> instead runs the perf workloads over seeds 1..n and
     * reports mean/min/max per size (perf builds only). */
    for (int i = 1; i < argc; i++)
    {
        if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc)
        {
            seed = (unsigned int)strtoul(argv[i + 1], NULL, 10);
            i++;
        }
        else if (strcmp(argv[i], "--sweep") == 0 && i + 1 < argc)
        {
            sweep_seeds = (int)strtol(argv[i + 1], NULL, 10);
            i++;
        }
        else if (strcmp(argv[i], "--reps") == 0 && i + 1 < argc)
        {
            g_perf_reps = (int)strtol(argv[i + 1], NULL, 10);
            if (g_perf_reps < 1)
            {
                fprintf(stderr, "--reps must be >= 1\n");
                return 2;
            }
            i++;
        }
        else
        {
            fprintf(stderr, "usage: %s [--seed <n>] [--sweep <n>] [--reps <k>]\n", argv[0]);
            return 2;
        }
    }
    srand(seed);
    printf("seed=%u\n", seed);

    /* These are defined as globals in the real build; define test copies here. */
    g_sort_case_sensitive = 0;
    g_plugin_image_list = 0;

#define RUN(name) do { \
        if (name()) { failed++; fprintf(stderr, "FAIL: %s\n", #name); } \
        else { printf("OK: %s\n", #name); } \
    } while (0)

    RUN(test_cmp_img_case_sensitive);
    RUN(test_cmp_img_case_insensitive);
    RUN(test_cmp_img_equal_names);
    RUN(test_cmp_img_prefix_equal_stability_tie);
    RUN(test_msort_empty);
    RUN(test_msort_single);
    RUN(test_msort_reverse_order);
    RUN(test_msort_duplicate_names_stable);
    RUN(test_msort_large_random);
    RUN(test_prod_msort_parity);
    RUN(test_make_item_long_name_copies_and_truncates);
    RUN(test_cmp_img_long_names_differing_after_byte64);
    RUN(test_msort_long_names_stable_and_ordered);
    RUN(test_swap_preserves_neighbors);
    RUN(test_plugin_list_index_mode);
    RUN(test_cmp_subdir_parent_before_child);
    RUN(test_cmp_subdir_deep_child_last);
    RUN(test_cmp_subdir_equal_dirs);
    RUN(test_cmp_subdir_case_insensitive);
    RUN(test_cmp_subdir_case_sensitive);
    RUN(test_cmp_subdir_plugin_list_mode);
    RUN(test_cmp_subdir_empty_dir_vs_nonempty);
#if VENTOY_SORT_TEST_PERF
    RUN(test_cmp_subdir_equal_dirs_preserve_insertion_order);
    RUN(test_cmp_subdir_equal_dirs_msort_preserves_order);
#endif
    RUN(test_toggle_case_sensitive_does_not_corrupt_order);
    RUN(test_toggle_case_sensitive_stress_multi_phase);
#if VENTOY_SORT_TEST_PERF
    if (sweep_seeds > 0)
    {
        if (perf_img_sweep(sweep_seeds))
        {
            failed++;
            fprintf(stderr, "FAIL: perf_img_sweep\n");
        }
        if (perf_subdir_sweep(sweep_seeds))
        {
            failed++;
            fprintf(stderr, "FAIL: perf_subdir_sweep\n");
        }
    }
    else
    {
        if (perf_mode_run())
        {
            failed++;
            fprintf(stderr, "FAIL: perf_mode_run\n");
        }
        else
        {
            printf("OK: perf_mode_run\n");
        }

        if (perf_subdir_run())
        {
            failed++;
            fprintf(stderr, "FAIL: perf_subdir_run\n");
        }
        else
        {
            printf("OK: perf_subdir_run\n");
        }
    }
#else
    if (sweep_seeds > 0 || g_perf_reps > 0)
    {
        fprintf(stderr, "FAIL: --sweep/--reps require a perf build "
                        "(use build_sort_test.py --perf --sweep <n> / --reps <k>)\n");
        failed++;
    }
#endif

    return failed ? 1 : 0;
}
