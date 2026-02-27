/*
 * SPDX-License-Identifier: BSD-2-Clause-Patent
 *
 * Copyright (c) 2026, SUSE LLC
 * Generated with assistance of Gemini CLI (Gemini 3)
 *
 * ovmf_vars_set.c - UEFI Variable Store Modification Tool for NVMe-oF
 *
 * This tool parses a configuration file and updates/adds NVMe-oF
 * configuration variables in an OVMF variable store.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <ctype.h>

#define PACKED __attribute__((packed))

/*
 * UEFI Basic Types and Headers
 */

typedef struct {
	uint32_t Data1;
	uint16_t Data2;
	uint16_t Data3;
	uint8_t Data4[8];
} PACKED efi_guid_t;

typedef struct {
	uint8_t Addr[16];
} PACKED EFI_IP_ADDRESS;

/*
 * NVMe-oF Configuration Structures (per EDK2 NetworkPkg)
 */

typedef struct {
	uint16_t NvmeofSubsysPortId;
	uint8_t Enabled;
	uint8_t NvmeofIpMode;
	EFI_IP_ADDRESS NvmeofSubsysHostIP;
	EFI_IP_ADDRESS NvmeofSubsysHostSubnetMask;
	EFI_IP_ADDRESS NvmeofSubsysHostGateway;
	uint8_t HostInfoDhcp;
	uint8_t NvmeofSubsysInfoDhcp;
	EFI_IP_ADDRESS NvmeofSubSystemIp;
	char ServerName[224];
	uint8_t NvmeofPrefixLength;
	uint16_t NvmeofTransportPort;
	uint16_t NvmeofSubsysControllerId;
	char NvmeofSubsysNid[64];
	char NvmeofSubsysNqn[224];
	efi_guid_t NvmeofTransportGuid;
	uint16_t NvmeofTimeout;
	uint8_t NvmeofRetryCount;
	uint8_t NvmeofDnsMode;
	uint8_t NvmeofSecurityEnabled;
	char SecurityKeyPath[255];
	uint16_t RouteMetric;
	char HostName[224];
	char NvmeofHostNqnOverride[224];
	uint8_t NvmeofHostIdOverride[16];
	uint8_t HostOverrideEnable;
} PACKED NVMEOF_SUBSYSTEM_CONFIG_NVDATA;

typedef struct {
	uint8_t NicIndex;
	uint8_t DhcpSuccess;
	uint8_t ValidnBFTPath;
	uint8_t ValidPath;
	uint8_t AutoConfigureMode;
	char AttemptName[12];
	char MacString[96];
	EFI_IP_ADDRESS PrimaryDns;
	EFI_IP_ADDRESS SecondaryDns;
	EFI_IP_ADDRESS DhcpServer;
	NVMEOF_SUBSYSTEM_CONFIG_NVDATA SubsysConfigData;
	uint8_t NvmeofAuthType;
	uint8_t AutoConfigureSuccess;
	uint8_t Actived;
} PACKED NVMEOF_ATTEMPT_CONFIG_NVDATA;

typedef struct {
	uint8_t NvmeOfEnabled;
	uint8_t NvmeOfTargetCount;
	uint16_t DriverVersion;
	char NvmeofHostNqn[224];
	uint8_t NvmeofHostId[16];
	uint16_t   NvmeofHostSecurityPath[255];
} PACKED NVMEOF_GLOBAL_DATA;

/* Variable entry headers */
typedef struct {
	uint16_t StartId;
	uint8_t State;
	uint8_t Reserved;
	uint32_t Attributes;
	uint32_t NameSize;
	uint32_t DataSize;
	efi_guid_t VendorGuid;
} PACKED VARIABLE_HEADER;

typedef struct {
	uint16_t StartId;
	uint8_t State;
	uint8_t Reserved;
	uint32_t Attributes;
	uint64_t MonotonicCount;
	uint8_t TimeStamp[16];
	uint32_t PubKeyIndex;
	uint32_t NameSize;
	uint32_t DataSize;
	efi_guid_t VendorGuid;
} PACKED AUTH_VARIABLE_HEADER;

static const uint8_t gGuidBytes[] = {
	0xe7, 0xca, 0x09, 0x15, 0x44, 0x70, 0x92, 0x43, 0xa2, 0x47, 0x3f, 0x87, 0x0a, 0x19, 0x71, 0x42
};

/* Parses UUID strings (with or without dashes) into bytes */
void parse_uuid(const char *s, uint8_t *out)
{
	unsigned int v[16];
	if (sscanf(s, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		   &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7],
		   &v[8], &v[9], &v[10], &v[11], &v[12], &v[13], &v[14], &v[15]) == 16) {
		for (int i = 0; i < 16; i++)
			out[i] = (uint8_t)v[i];
	} else if (sscanf(s, "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
			  &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7],
			  &v[8], &v[9], &v[10], &v[11], &v[12], &v[13], &v[14], &v[15]) == 16) {
		for (int i = 0; i < 16; i++)
			out[i] = (uint8_t)v[i];
	}
}

/* Parses IP addresses and optional prefix lengths */
void parse_ip(const char *s, EFI_IP_ADDRESS *out, int mode, uint8_t *prefix)
{
	char buf[256];
	memset(out, 0, 16);
	strncpy(buf, s, 255);
	buf[255] = 0;
	char *slash = strchr(buf, '/');
	if (slash) {
		*slash = 0;
		if (prefix)
			*prefix = atoi(slash + 1);
	}
	inet_pton(mode == 0 ? AF_INET : AF_INET6, buf, out->Addr);
}

/* Appends a new variable entry to the store */
void add_variable(uint8_t **ptr, const char *name, void *data, uint32_t ds)
{
	AUTH_VARIABLE_HEADER *av = (AUTH_VARIABLE_HEADER *)*ptr;
	memset(av, 0, sizeof(AUTH_VARIABLE_HEADER));
	av->StartId = 0x55AA;
	av->State = 0x3f;
	av->Attributes = 0x03;
	uint32_t ns = (strlen(name) + 1) * 2;
	av->NameSize = ns;
	av->DataSize = ds;
	memcpy(&av->VendorGuid, gGuidBytes, 16);
	uint16_t *name_u16 = (uint16_t *)((*ptr) + 60);
	for (int i = 0; name[i]; i++)
		name_u16[i] = (uint16_t)name[i];
	name_u16[strlen(name)] = 0;
	memcpy((*ptr) + 60 + ns, data, ds);
	uint32_t total = (60 + ns + ds + 3) & ~3;
	*ptr += total;
}

int main(int argc, char **argv)
{
	if (argc < 3) {
		printf("Usage: %s <OVMF_VARS.fd> <config>\n", argv[0]);
		return 1;
	}

	FILE *cf = fopen(argv[2], "r");
	if (!cf) {
		perror("fopen config");
		return 1;
	}

	NVMEOF_GLOBAL_DATA g = {.NvmeOfEnabled = 1, .DriverVersion = 10};
	NVMEOF_ATTEMPT_CONFIG_NVDATA a[4];
	memset(a, 0, sizeof(a));
	int count = 0, in = 0;
	char line[1024];

	/* Configuration File Parser */
	while (fgets(line, sizeof(line), cf)) {
		char *p = line;
		while (isspace(*p)) p++;
		if (*p == '#' || *p == '\0') continue;
		char *e = p + strlen(p) - 1;
		while (e > p && isspace(*e)) *e-- = '\0';

		if (strcmp(p, "$Start") == 0) {
			if (count < 4) in = 1;
			continue;
		}
		if (strcmp(p, "$End") == 0) {
			if (in) { count++; in = 0; }
			continue;
		}

		char *sep = strchr(p, ':');
		if (!sep) continue;
		*sep = '\0';
		char *k = p, *v = sep + 1;

		if (!in) {
			if (strcmp(k, "HostNqn") == 0)
				strncpy(g.NvmeofHostNqn, v, 223);
			else if (strcmp(k, "HostId") == 0)
				parse_uuid(v, g.NvmeofHostId);
		} else {
			NVMEOF_ATTEMPT_CONFIG_NVDATA *ca = &a[count];
			NVMEOF_SUBSYSTEM_CONFIG_NVDATA *cs = &ca->SubsysConfigData;
			if (strcmp(k, "AttemptName") == 0)
				strncpy(ca->AttemptName, v, 11);
			else if (strcmp(k, "MacString") == 0)
				strncpy(ca->MacString, v, 95);
			else if (strcmp(k, "TargetPort") == 0)
				cs->NvmeofSubsysPortId = atoi(v);
			else if (strcmp(k, "IpMode") == 0)
				cs->NvmeofIpMode = atoi(v);
			else if (strcmp(k, "Enabled") == 0)
				cs->Enabled = atoi(v);
			else if (strcmp(k, "TargetIp") == 0)
				parse_ip(v, &cs->NvmeofSubSystemIp, cs->NvmeofIpMode, NULL);
			else if (strcmp(k, "LocalIp") == 0)
				parse_ip(v, &cs->NvmeofSubsysHostIP, cs->NvmeofIpMode, NULL);
			else if (strcmp(k, "SubnetMask") == 0)
				parse_ip(v, &cs->NvmeofSubsysHostSubnetMask, cs->NvmeofIpMode, &cs->NvmeofPrefixLength);
			else if (strcmp(k, "Gateway") == 0)
				parse_ip(v, &cs->NvmeofSubsysHostGateway, cs->NvmeofIpMode, NULL);
			else if (strcmp(k, "NQN") == 0)
				strncpy(cs->NvmeofSubsysNqn, v, 223);
			else if (strcmp(k, "NID") == 0)
				strncpy(cs->NvmeofSubsysNid, v, 63);
			else if (strcmp(k, "ControllerId") == 0)
				cs->NvmeofSubsysControllerId = atoi(v);
			else if (strcmp(k, "TransportPort") == 0)
				cs->NvmeofTransportPort = atoi(v);
			else if (strcmp(k, "ConnectTimeout") == 0)
				cs->NvmeofTimeout = atoi(v);
			else if (strcmp(k, "ConnectRetryCount") == 0)
				cs->NvmeofRetryCount = atoi(v);
			else if (strcmp(k, "DnsMode") == 0)
				cs->NvmeofDnsMode = (strcasecmp(v, "TRUE") == 0);
			else if (strcmp(k, "RouteMetric") == 0)
				cs->RouteMetric = atoi(v);
			else if (strcmp(k, "HostName") == 0)
				strncpy(cs->HostName, v, 223);
			else if (strcmp(k, "InitiatorInfoFromDhcp") == 0)
				cs->HostInfoDhcp = (strcasecmp(v, "TRUE") == 0 || atoi(v) == 1);
			else if (strcmp(k, "TargetInfoFromDhcp") == 0)
				cs->NvmeofSubsysInfoDhcp = (strcasecmp(v, "TRUE") == 0 || atoi(v) == 1);
		}
	}
	fclose(cf);
	g.NvmeOfTargetCount = count;

	int fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	struct stat st;
	fstat(fd, &st);
	uint8_t *m = mmap(NULL, st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (m == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	int up_at = 0, up_gb = 0;
	uint8_t *last_ptr = NULL;

	/* Search and Update existing variables */
	for (size_t i = 0; i <= st.st_size - 16; i++) {
		if (memcmp(m + i, gGuidBytes, 16) == 0) {
			uint8_t *hs;
			int au;
			if (i >= 44 && *(uint16_t *)(m + i - 44) == 0x55AA) {
				hs = m + i - 44;
				au = 1;
			} else if (i >= 16 && *(uint16_t *)(m + i - 16) == 0x55AA) {
				hs = m + i - 16;
				au = 0;
			} else {
				continue;
			}
			uint32_t ns = *(uint32_t *)(hs + (au ? 36 : 8));
			uint32_t ds = *(uint32_t *)(hs + (au ? 40 : 12));
			uint16_t *nm = (uint16_t *)(hs + (au ? 60 : 32));
			char nb[256] = {0};
			for (int j = 0; j < (ns / 2) && j < 255; j++)
				nb[j] = (char)nm[j];
			uint8_t *d = (uint8_t *)nm + ns;
			if (strcmp(nb, "Nvmeof_Attemptconfig") == 0 || strcmp(nb, "NvmeofGlobalData") == 0) {
				VARIABLE_HEADER *vh = (VARIABLE_HEADER *)hs;
				vh->State = 0x3f;
				vh->Attributes = 0x03;
				if (strcmp(nb, "Nvmeof_Attemptconfig") == 0) {
					memcpy(d, a, ds < sizeof(a) ? ds : sizeof(a));
					printf("Updated Nvmeof_Attemptconfig\n");
					up_at = 1;
				} else {
					memcpy(d, &g, ds < sizeof(g) ? ds : sizeof(g));
					printf("Updated NvmeofGlobalData\n");
					up_gb = 1;
				}
			}
			last_ptr = hs + (((au ? 60 : 32) + ns + ds + 3) & ~3);
		}
	}

	/* Append new variables if not found */
	if (!up_at || !up_gb) {
		if (!last_ptr) {
			for (size_t i = 0; i < st.st_size - 16; i++) {
				if (memcmp(m + i, "\x78\x2c\xf3\xaa\x7b\x94\x9a\x43\xa1\x80\x2e\x14\x4e\xc3\x77\x92", 16) == 0) {
					last_ptr = m + i + 28;
					break;
				}
			}
		}
		if (last_ptr) {
			while (last_ptr + 60 < m + st.st_size && *(uint16_t *)last_ptr == 0x55AA) {
				uint32_t ns = *(uint32_t *)(last_ptr + 36), ds = *(uint32_t *)(last_ptr + 40);
				last_ptr += (60 + ns + ds + 3) & ~3;
			}
			if (!up_at) {
				add_variable(&last_ptr, "Nvmeof_Attemptconfig", a, sizeof(a));
				printf("Added Nvmeof_Attemptconfig\n");
			}
			if (!up_gb) {
				add_variable(&last_ptr, "NvmeofGlobalData", &g, sizeof(g));
				printf("Added NvmeofGlobalData\n");
			}
		}
	}

	msync(m, st.st_size, MS_SYNC);
	munmap(m, st.st_size);
	close(fd);
	return 0;
}
