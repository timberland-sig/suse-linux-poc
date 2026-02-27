/*
 * SPDX-License-Identifier: BSD-2-Clause-Patent
 *
 * Copyright (c) 2026, SUSE LLC
 * Generated with assistance of Gemini CLI (Gemini 3)
 *
 * ovmf_vars_dump.c - UEFI Variable Store Dump Tool for NVMe-oF
 *
 * This tool parses OVMF/EDK2 variable stores (standard and authenticated)
 * and decodes NVMe-oF configuration variables.
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

typedef struct {
	efi_guid_t Signature;
	uint32_t Size;
	uint8_t Format;
	uint8_t State;
	uint16_t Reserved;
	uint32_t Reserved1;
} PACKED VARIABLE_STORE_HEADER;

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
	uint16_t NvmeofHostSecurityPath[255];
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

/* Standard GUIDs used by OVMF/EDK2 */
static const efi_guid_t gVariableStoreGuid = {
	0xddcf3616, 0x3275, 0x4164, {0x98, 0xb6, 0xfe, 0x85, 0x70, 0x7f, 0xfe, 0x7d}
};
static const efi_guid_t gAuthVariableStoreGuid = {
	0xaaf32c78, 0x947b, 0x439a, {0xa1, 0x80, 0x2e, 0x14, 0x4e, 0xc3, 0x77, 0x92}
};
static const efi_guid_t gNvmeofConfigGuid = {
	0x1509cae7, 0x7044, 0x4392, {0xa2, 0x47, 0x3f, 0x87, 0x0a, 0x19, 0x71, 0x42}
};

/* Helper to print GUID in standard format */
void print_guid(efi_guid_t guid)
{
	printf("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
	       guid.Data1, guid.Data2, guid.Data3,
	       guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3],
	       guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
}

/* Basic UCS-2 to ASCII converter for variable names */
void print_ucs2(uint16_t *name, uint32_t name_size)
{
	for (uint32_t i = 0; i < name_size / 2; i++) {
		uint16_t c = name[i];
		if (c == 0)
			break;
		if (c >= 0x20 && c <= 0x7E)
			putchar((char)c);
		else
			putchar('.');
	}
}

/* Formats and prints IP addresses based on the IP mode */
void print_ip(EFI_IP_ADDRESS *ip, int mode)
{
	char buf[INET6_ADDRSTRLEN];
	if (mode == 0)
		inet_ntop(AF_INET, ip->Addr, buf, sizeof(buf));
	else
		inet_ntop(AF_INET6, ip->Addr, buf, sizeof(buf));
	printf("%s", buf);
}

/* Pretty-prints the NVMe-oF Attempt Configuration structure */
void print_attempt_config(NVMEOF_ATTEMPT_CONFIG_NVDATA *cfg, int index)
{
	NVMEOF_SUBSYSTEM_CONFIG_NVDATA *sub = &cfg->SubsysConfigData;

	printf("  Attempt [%d]:\n", index);
	printf("    Attempt Name: %s\n", cfg->AttemptName);
	printf("    MAC String:   %s\n", cfg->MacString);
	printf("    Active:       %s\n", cfg->Actived ? "Yes" : "No");
	printf("    Subsys IP:    ");
	print_ip(&sub->NvmeofSubSystemIp, sub->NvmeofIpMode);
	printf("\n    Subsys Port:  %u\n", sub->NvmeofTransportPort);
	printf("    Subsys PortId:%u\n", sub->NvmeofSubsysPortId);
	printf("    Subsys NQN:   %s\n", sub->NvmeofSubsysNqn);
	printf("    Subsys NID:   %s\n", sub->NvmeofSubsysNid);
	printf("    Enabled:      %s\n", sub->Enabled ? "Yes" : "No");
	printf("    Host DHCP:    %s\n", sub->HostInfoDhcp ? "Enabled" : "Disabled");
	printf("    Subsys DHCP:  %s\n", sub->NvmeofSubsysInfoDhcp ? "Enabled" : "Disabled");
	printf("    IP Mode:      %u (%s)\n", sub->NvmeofIpMode, sub->NvmeofIpMode == 0 ? "IPv4" : "IPv6");
	printf("    Local IP:     ");
	print_ip(&sub->NvmeofSubsysHostIP, sub->NvmeofIpMode);
	printf("\n    Subnet Mask:  ");
	print_ip(&sub->NvmeofSubsysHostSubnetMask, sub->NvmeofIpMode);
	if (sub->NvmeofIpMode != 0)
		printf("/%u", sub->NvmeofPrefixLength);
	printf("\n    Gateway:      ");
	print_ip(&sub->NvmeofSubsysHostGateway, sub->NvmeofIpMode);
	printf("\n    DNS Mode:     %s\n", sub->NvmeofDnsMode ? "TRUE" : "FALSE");
	printf("    HostName:     %s\n", sub->HostName);
	printf("    ServerName:   %s\n", sub->ServerName);
}

/* Pretty-prints the NVMe-oF Global Data structure */
void print_global_data(NVMEOF_GLOBAL_DATA *glob)
{
	printf("  [Global Data]\n");
	printf("    Enabled:      %s\n", glob->NvmeOfEnabled ? "Yes" : "No");
	printf("    Target Count: %u\n", glob->NvmeOfTargetCount);
	printf("    Driver Ver:   %u\n", glob->DriverVersion);
	printf("    Host NQN:     %s\n", glob->NvmeofHostNqn);
	printf("    Host ID:      ");
	for (int i = 0; i < 16; i++)
		printf("%02x ", glob->NvmeofHostId[i]);
	printf("\n");
}

/* Core iterator that walks through the variable stream */
void dump_variable_stream(uint8_t *base, uint8_t *ptr, uint8_t *end, int is_auth, int verbose)
{
	size_t header_size = is_auth ? sizeof(AUTH_VARIABLE_HEADER) : sizeof(VARIABLE_HEADER);

	while (ptr + header_size <= end) {
		uint16_t start_id = *(uint16_t *)ptr;
		if (start_id != 0x55AA)
			break;

		uint8_t state = ptr[2];
		uint32_t name_size, data_size, attr;
		efi_guid_t guid;
		uint16_t *name_u16;

		if (is_auth) {
			AUTH_VARIABLE_HEADER *av = (AUTH_VARIABLE_HEADER *)ptr;
			name_size = av->NameSize;
			data_size = av->DataSize;
			guid = av->VendorGuid;
			attr = av->Attributes;
			name_u16 = (uint16_t *)(ptr + sizeof(AUTH_VARIABLE_HEADER));
		} else {
			VARIABLE_HEADER *v = (VARIABLE_HEADER *)ptr;
			name_size = v->NameSize;
			data_size = v->DataSize;
			guid = v->VendorGuid;
			attr = v->Attributes;
			name_u16 = (uint16_t *)(ptr + sizeof(VARIABLE_HEADER));
		}

		/* Variable is in an active/valid state */
		if (state == 0xFC || state == 0x3F) {
			char nb[256] = {0};
			for (int i = 0; i < (name_size / 2) && i < 255; i++)
				nb[i] = (char)name_u16[i];

			int is_nvmeof = (memcmp(&guid, &gNvmeofConfigGuid, sizeof(efi_guid_t)) == 0);
			int should_print = verbose || (is_nvmeof && (strcmp(nb, "Nvmeof_Attemptconfig") == 0 ||
								     strcmp(nb, "NvmeofGlobalData") == 0));

			if (should_print) {
				printf("[%08tx] Variable: %s\n", ptr - base, nb);
				printf("  GUID:  ");
				print_guid(guid);
				printf("\n  Attr:  0x%08x, State: 0x%02x\n", attr, state);
				uint8_t *data_ptr = (uint8_t *)name_u16 + name_size;

				if (is_nvmeof) {
					if (strcmp(nb, "Nvmeof_Attemptconfig") == 0) {
						int count = data_size / sizeof(NVMEOF_ATTEMPT_CONFIG_NVDATA);
						for (int i = 0; i < count; i++)
							print_attempt_config((NVMEOF_ATTEMPT_CONFIG_NVDATA *)(data_ptr + i * sizeof(NVMEOF_ATTEMPT_CONFIG_NVDATA)), i + 1);
					} else if (strcmp(nb, "NvmeofGlobalData") == 0) {
						if (data_size >= sizeof(NVMEOF_GLOBAL_DATA))
							print_global_data((NVMEOF_GLOBAL_DATA *)data_ptr);
					} else if (verbose) {
						printf("  Data:  (%u bytes) ", data_size);
						uint32_t dsize = data_size > 32 ? 32 : data_size;
						for (uint32_t i = 0; i < dsize; i++)
							printf("%02x ", data_ptr[i]);
						printf("\n");
					}
				} else if (verbose) {
					printf("  Data:  (%u bytes) ", data_size);
					uint32_t dsize = data_size > 32 ? 32 : data_size;
					for (uint32_t i = 0; i < dsize; i++)
						printf("%02x ", data_ptr[i]);
					printf("\n");
				}
				printf("------------------------------------------------\n");
			}
		}

		/* UEFI variables are 4-byte aligned */
		uint32_t total = (header_size + name_size + data_size + 3) & ~3;
		if (total < header_size)
			break;
		ptr += total;
	}
}

int main(int argc, char **argv)
{
	int verbose = 0;
	const char *file = NULL;

	/* Simple argument parsing */
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-v") == 0)
			verbose = 1;
		else
			file = argv[i];
	}

	if (!file) {
		printf("Usage: %s [-v] <file>\n", argv[0]);
		return 1;
	}

	int fd = open(file, O_RDONLY);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	struct stat st;
	fstat(fd, &st);

	uint8_t *m = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (m == MAP_FAILED) {
		perror("mmap");
		close(fd);
		return 1;
	}

	/* Scan for Variable Store Header Signatures */
	for (size_t i = 0; i <= st.st_size - sizeof(VARIABLE_STORE_HEADER); i++) {
		int auth = -1;
		if (memcmp(m + i, &gVariableStoreGuid, 16) == 0)
			auth = 0;
		else if (memcmp(m + i, &gAuthVariableStoreGuid, 16) == 0)
			auth = 1;

		if (auth != -1) {
			VARIABLE_STORE_HEADER *h = (VARIABLE_STORE_HEADER *)(m + i);
			dump_variable_stream(m, m + i + sizeof(VARIABLE_STORE_HEADER), m + i + h->Size, auth, verbose);
			i += h->Size - 1; /* Skip ahead to end of this store */
		}
	}

	munmap(m, st.st_size);
	close(fd);
	return 0;
}
