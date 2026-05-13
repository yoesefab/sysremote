/*
 * sysremote_fork.c — Lot 3: Parallélisation par fork()
 * Compilation: gcc -Wall -Werror -O2 -o sysremote_fork sysremote_fork.c
 */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <errno.h>
#include <getopt.h>
#include <time.h>

#define MAX_HOSTS    1024
#define MAX_LINE     256
#define MAX_CMD      2048
#define DEFAULT_TIMEOUT   10
#define DEFAULT_MAX_PROCS 0

typedef struct {
    char host[MAX_LINE];
    pid_t pid;
    int   exit_code;
    int   active;
} HostJob;

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

static void child_exec(const Config *cfg, const char *host) {
    char log_path[1024];
    char safe_host[MAX_LINE];
    safe_name(host, safe_host, sizeof(safe_host));
    snprintf(log_path, sizeof(log_path), "%s/%s.log", cfg->log_dir, safe_host);

    int log_fd = open(log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (log_fd < 0) { perror("open log"); _exit(127); }
    dup2(log_fd, STDOUT_FILENO);
    dup2(log_fd, STDERR_FILENO);
    close(log_fd);

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", cfg->port);
    char connect_timeout[64];
    snprintf(connect_timeout, sizeof(connect_timeout), "ConnectTimeout=%d", cfg->timeout);
    char user_host[MAX_LINE + 64];

    if (cfg->scp_mode) {
        char dst[MAX_LINE * 2 + 128];
        snprintf(dst, sizeof(dst), "%s@%s:%s", cfg->user, host, cfg->scp_dst);
        char *const argv[] = {
            "scp", "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes", "-P", port_str,
            (char *)cfg->scp_src, dst, NULL
        };
        execvp("scp", argv);
    } else {
        snprintf(user_host, sizeof(user_host), "%s@%s", cfg->user, host);
        char *const argv[] = {
            "ssh", "-o", "StrictHostKeyChecking=no",
            "-o", connect_timeout, "-o", "BatchMode=yes",
            "-p", port_str, user_host, (char *)cfg->command, NULL
        };
        execvp("ssh", argv);
    }
    perror("execvp");
    _exit(127);
}

static int wait_for_slot(HostJob *jobs, int n_jobs, int *ok, int *fail) {
    int status;
    pid_t pid = waitpid(-1, &status, 0);
    if (pid <= 0) return -1;
    for (int i = 0; i < n_jobs; i++) {
        if (jobs[i].pid == pid && jobs[i].active) {
            jobs[i].active = 0;
            jobs[i].exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
            printf("[fork] [%s] rc=%d\n", jobs[i].host, jobs[i].exit_code);
            fflush(stdout);
            if (jobs[i].exit_code == 0) (*ok)++; else (*fail)++;
            return 0;
        }
    }
    return -1;
}

static int run_fork(Config *cfg) {
    HostJob jobs[MAX_HOSTS];
    memset(jobs, 0, sizeof(jobs));
    int running = 0, ok = 0, fail = 0;
    long t_start = now_ms();

    printf("[fork] %d hôtes, max-procs=%d\n", cfg->count, cfg->max_procs);

    for (int i = 0; i < cfg->count; i++) {
        if (cfg->max_procs > 0) {
            while (running >= cfg->max_procs) {
                wait_for_slot(jobs, cfg->count, &ok, &fail);
                running--;
            }
        }

        pid_t pid = fork();
        if (pid < 0) { perror("fork"); fail++; continue; }
        if (pid == 0) { child_exec(cfg, cfg->hosts[i]); _exit(127); }

        jobs[i].pid    = pid;
        jobs[i].active = 1;
        strncpy(jobs[i].host, cfg->hosts[i], MAX_LINE - 1);
        running++;
    }

    int status;
    pid_t pid;
    while ((pid = waitpid(-1, &status, 0)) > 0) {
        for (int i = 0; i < cfg->count; i++) {
            if (jobs[i].pid == pid && jobs[i].active) {
                jobs[i].active = 0;
                jobs[i].exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
                printf("[fork] [%s] rc=%d\n", jobs[i].host, jobs[i].exit_code);
                fflush(stdout);
                if (jobs[i].exit_code == 0) ok++; else fail++;
                break;
            }
        }
    }

    long elapsed = now_ms() - t_start;
    printf("[fork] OK=%d FAIL=%d durée=%ldms\n", ok, fail, elapsed);
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
    snprintf(cfg->log_dir, sizeof(cfg->log_dir), "/tmp/sysremote_fork_%d", getpid());
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
    return run_fork(&cfg);
}
