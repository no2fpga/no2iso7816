CORE := no2iso7816

RTL_SRCS_no2iso7816 = $(addprefix rtl/, \
	iso7816_brg_sync.v \
	iso7816_core.v \
	iso7816_wb.v \
)

TESTBENCHES_no2iso7816 := \
	iso7816_brg_sync_tb \
	iso7816_core_tb \
	$(NULL)

include $(NO2BUILD_DIR)/core-magic.mk
