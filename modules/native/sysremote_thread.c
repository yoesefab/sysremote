/*
 * sysremote_thread.c — Lot 3: Parallélisation par pthread
 * Compilation: gcc -Wall -Werror -O2 -o sysremote_thread sysremote_thread.c -lpthread
 */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <semaphore.h>
#include <errno.h>
#include <getopt.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>

#define MAX_HOSTS    1024
#define MAX_LINE     256
#define MAX_CMD      2048
#define DEFAULT_TIMEOUT   10
#define DEFAULT_MAX_PROCS 0

typedef struct {
    const char *user;
    int         port;
    int         timeout;
    const char *log_dir;
    const char *command;
    const char *scp_src;
    const char *scp_dst;
    int         scp_mode;
    sem_t      *slot_sem;
    char        host[MAX_LINE];
    int         exit_code;
} ThreadArg;

typedef struct {
    char  hosts[MAX_HOSTS][MAX_LINE];
    int   count;
    char  user[64];
    int   port;
    int   timeout;
    int   max_procs;
    char  log_dir[256];
    char  command[MAX_CMD];
    char  scp_src[MAX_LINE];
    char  scp_dst[MAX_LINE];
    int   scp_mode;
} Config;

static pthread_mutex_t print_mutex = PTHREAD_MUTEX_INITIALIZER;

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static void safe_name(const char *input, char *output, size_t output_size) {
    size_t j = 0;
    if (output_size == 0) return;
    for (size_t i = 0; input[i] != '\0' && j + 1 < output_size; i++) {
        char c = input[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-') {
            output[j++] = c;
        } else {
            output[j++] = '_';
        }
    }
    output[j] = '\0';
}

static int load_hosts(Config *cfg, const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }
    char line[MAX_LINE];
    cfg->count = 0;
    while (fgets(line, sizeof(line), f) && cfg->count < MAX_HOSTS) {
        line[strcspn(line, "\n")] = '\0';
        if (line[0] == '#' || line[0] == '\0') continue;
        memcpy(cfg->hosts[cfg->count], line, MAX_LINE - 1);
        cfg->hosts[cfg->count][MAX_LINE - 1] = '\0';
        cfg->count++;
    }
    fclose(f);
    return cfg->count;
}

static int exec_cmd(const ThreadArg *arg) {
    char log_path[1024];
    char safe_host[MAX_LINE];
    char port_str[16];
    char connect_timeout[64];
    char user_host[MAX_LINE + 64];
    int log_fd;
    int status;
    pid_t pid;

    safe_name(arg->host, safe_host, sizeof(safe_host));
    snprintf(log_path, sizeof(log_path), "%s/%s.log", arg->log_dir, safe_host);
    snprintf(port_str, sizeof(port_str), "%d", arg->port);
    snprintf(connect_timeout, sizeof(connect_timeout), "ConnectTimeout=%d", arg->timeout);

    pid = fork();
    if (pid < 0) return 127;
    if (pid == 0) {
        log_fd = open(log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (log_fd < 0) _exit(127);
        dup2(log_fd, STDOUT_FILENO);
        dup2(log_fd, STDERR_FILENO);
        close(log_fd);

        if (arg->scp_mode) {
            char dst[MAX_LINE * 2 + 128];
            snprintf(dst, sizeof(dst), "%s@%s:%s", arg->user, arg->host, arg->scp_dst);
            char *const argv[] = {
                "scp", "-o", "StrictHostKeyChecking=no",
                "-o", "BatchMode=yes", "-P", port_str,
                (char *)arg->scp_src, dst, NULL
            };
            execvp("scp", argv);
        } else {
            snprintf(user_host, sizeof(user_host), "%s@%s", arg->user, arg->host);
            char *const argv[] = {
                "ssh", "-o", "StrictHostKeyChecking=no",
                "-o", connect_timeout, "-o", "BatchMode=yes",
                "-p", port_str, user_host, (char *)arg->command, NULL
            };
            execvp("ssh", argv);
        }
        _exit(127);
    }

    if (waitpid(pid, &status, 0) < 0) return 127;
    return status;
}

static void *thread_worker(void *data) {
    ThreadArg *arg = (ThreadArg *)data;

    if (arg->slot_sem) sem_wait(arg->slot_sem);

    int rc = exec_cmd(arg);
    arg->exit_code = WIFEXITED(rc) ? WEXITSTATUS(rc) : -1;

    pthread_mutex_lock(&print_mutex);
    printf("[thread] [%s] rc=%d\n", arg->host, arg->exit_code);
    fflush(stdout);
    pthread_mutex_unlock(&print_mutex);

    if (arg->slot_sem) sem_post(arg->slot_sem);
    return NULL;
}

static int run_thread(Config *cfg) {
    pthread_t  tids[MAX_HOSTS];
    ThreadArg  args[MAX_HOSTS];
    sem_t      slot_sem;
    sem_t     *sem_ptr = NULL;

    if (cfg->max_procs > 0) {
        if (sem_init(&slot_sem, 0, (unsigned)cfg->max_procs) != 0) {
            perror("sem_init"); return 1;
        }
        sem_ptr = &slot_sem;
    }

    printf("[thread] %d hôtes, max-procs=%d\n", cfg->count, cfg->max_procs);
    long t_start = now_ms();

    for (int i = 0; i < cfg->count; i++) {
        args[i].user     = cfg->user;
        args[i].port     = cfg->port;
        args[i].timeout  = cfg->timeout;
        args[i].log_dir  = cfg->log_dir;
        args[i].command  = cfg->command;
        args[i].scp_src  = cfg->scp_src;
        args[i].scp_dst  = cfg->scp_dst;
        args[i].scp_mode = cfg->scp_mode;
        args[i].slot_sem = sem_ptr;
        args[i].exit_code = -1;
        strncpy(args[i].host, cfg->hosts[i], MAX_LINE - 1);

        if (pthread_create(&tids[i], NULL, thread_worker, &args[i]) != 0) {
            perror("pthread_create");
            tids[i] = 0;
        }
    }

    int ok = 0, fail = 0;
    for (int i = 0; i < cfg->count; i++) {
        if (tids[i] != 0) pthread_join(tids[i], NULL);
        if (args[i].exit_code == 0) ok++; else fail++;
    }

    if (sem_ptr) sem_destroy(&slot_sem);

    long elapsed = now_ms() - t_start;
    printf("[thread] OK=%d FAIL=%d durée=%ldms\n", ok, fail, elapsed);
    return (fail > 0) ? 1 : 0;
}

static void parse_args(int argc, char **argv, Config *cfg, char **hosts_file) {
    static struct option long_opts[] = {
        {"hosts",     required_argument, 0, 'H'},
        {"user",      required_argument, 0, 'u'},
        {"port",      required_argument, 0, 'p'},
        {"timeout",   required_argument, 0, 'T'},
        {"log-dir",   required_argument, 0, 'L'},
        {"max-procs", required_argument, 0, 'n'},
        {"scp",       required_argument, 0, 'S'},
        {0, 0, 0, 0}
    };
    strncpy(cfg->user, getenv("USER") ? getenv("USER") : "root", 63);
    cfg->port = 22; cfg->timeout = DEFAULT_TIMEOUT;
    cfg->max_procs = DEFAULT_MAX_PROCS; cfg->scp_mode = 0;
    snprintf(cfg->log_dir, sizeof(cfg->log_dir), "/tmp/sysremote_thread_%d", getpid());
    *hosts_file = NULL;

    int opt, idx = 0;
    while ((opt = getopt_long(argc, argv, "H:u:p:T:L:n:S:", long_opts, &idx)) != -1) {
        switch (opt) {
            case 'H': *hosts_file = optarg; break;
            case 'u': strncpy(cfg->user, optarg, 63); break;
            case 'p': cfg->port    = atoi(optarg); break;
            case 'T': cfg->timeout = atoi(optarg); break;
            case 'L': strncpy(cfg->log_dir, optarg, 255); break;
            case 'n': cfg->max_procs = atoi(optarg); break;
            case 'S':
                strncpy(cfg->scp_src, optarg, MAX_LINE - 1);
                if (optind < argc) strncpy(cfg->scp_dst, argv[optind++], MAX_LINE - 1);
                cfg->scp_mode = 1; break;
            default:
                fprintf(stderr, "Usage: %s -H HOSTS [options] [-- CMD]\n", argv[0]);
                exit(1);
        }
    }
    if (!cfg->scp_mode && optind < argc) {
        cfg->command[0] = '\0';
        for (int i = optind; i < argc; i++) {
            if (i > optind) strncat(cfg->command, " ", MAX_CMD - strlen(cfg->command) - 1);
            strncat(cfg->command, argv[i], MAX_CMD - strlen(cfg->command) - 1);
        }
    }
}

int main(int argc, char **argv) {
    Config cfg; memset(&cfg, 0, sizeof(cfg));
    char *hosts_file = NULL;
    parse_args(argc, argv, &cfg, &hosts_file);

    if (!hosts_file) { fprintf(stderr, "ERREUR: -H requis\n"); return 1; }
    if (!cfg.scp_mode && cfg.command[0] == '\0') {
        fprintf(stderr, "ERREUR: commande requise après --\n"); return 1;
    }

    if (mkdir(cfg.log_dir, 0755) != 0 && errno != EEXIST) {
        perror("mkdir log-dir");
        return 1;
    }

    if (load_hosts(&cfg, hosts_file) < 0) return 1;
    return run_thread(&cfg);
}
