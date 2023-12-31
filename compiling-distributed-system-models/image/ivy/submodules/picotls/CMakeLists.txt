CMAKE_MINIMUM_REQUIRED(VERSION 2.8.11)
CMAKE_POLICY(SET CMP0003 NEW)

PROJECT(picotls)

FIND_PACKAGE(PkgConfig REQUIRED)

SET(CMAKE_C_FLAGS "-std=c99 -Wall -O2 -g ${CC_WARNING_FLAGS} ${CMAKE_C_FLAGS}")
INCLUDE_DIRECTORIES(${OPENSSL_INCLUDE_DIR} deps/cifra/src/ext deps/cifra/src deps/micro-ecc deps/picotest include)
SET(MINICRYPTO_LIBRARY_FILES
    deps/micro-ecc/uECC.c
    deps/cifra/src/aes.c
    deps/cifra/src/blockwise.c
    deps/cifra/src/chacha20.c
    deps/cifra/src/chash.c
    deps/cifra/src/curve25519.c
    deps/cifra/src/drbg.c
    deps/cifra/src/hmac.c
    deps/cifra/src/gcm.c
    deps/cifra/src/gf128.c
    deps/cifra/src/modes.c
    deps/cifra/src/poly1305.c
    deps/cifra/src/sha256.c
    deps/cifra/src/sha512.c)
SET(CORE_FILES
    lib/picotls.c
    lib/pembase64.c)

PKG_CHECK_MODULES(BROTLI_DEC libbrotlidec)
PKG_CHECK_MODULES(BROTLI_ENC libbrotlienc)
IF (BROTLI_DEC_FOUND AND BROTLI_ENC_FOUND)
    INCLUDE_DIRECTORIES(${BROTLI_DEC_INCLUDE_DIRS} ${BROTLI_ENC_INCLUDE_DIRS})
    LINK_DIRECTORIES(${BROTLI_DEC_LIBRARY_DIRS} ${BROTLI_ENC_LIBRARY_DIRS})
    SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DPICOTLS_USE_BROTLI=1")
    LIST(APPEND CORE_FILES
        lib/certificate_compression.c)
    LIST(APPEND CORE_EXTRA_LIBS ${BROTLI_DEC_LIBRARIES} ${BROTLI_ENC_LIBRARIES})
ENDIF ()

ADD_LIBRARY(picotls-core ${CORE_FILES})
TARGET_LINK_LIBRARIES(picotls-core ${CORE_EXTRA_LIBS})
ADD_LIBRARY(picotls-minicrypto ${MINICRYPTO_LIBRARY_FILES} lib/cifra.c lib/minicrypto-pem.c lib/uecc.c lib/asn1.c lib/ffx.c)
TARGET_LINK_LIBRARIES(picotls-minicrypto picotls-core)
ADD_EXECUTABLE(test-minicrypto.t ${MINICRYPTO_LIBRARY_FILES} deps/picotest/picotest.c t/picotls.c t/minicrypto.c lib/asn1.c lib/pembase64.c lib/ffx.c)

SET(TEST_EXES test-minicrypto.t)

FIND_PACKAGE(OpenSSL)
IF (OPENSSL_FOUND AND NOT (OPENSSL_VERSION VERSION_LESS "1.0.1"))
    MESSAGE(WARNING "Enabling OpenSSL support")
    INCLUDE_DIRECTORIES(${OPENSSL_INCLUDE_DIR})
    ADD_LIBRARY(picotls-openssl lib/openssl.c)
    TARGET_LINK_LIBRARIES(picotls-openssl ${OPENSSL_LIBRARIES} picotls-core ${CMAKE_DL_LIBS})
    ADD_EXECUTABLE(cli t/cli.c lib/pembase64.c)
    TARGET_LINK_LIBRARIES(cli picotls-openssl picotls-core resolv)
    ADD_EXECUTABLE(picotls-esni src/esni.c)
    TARGET_LINK_LIBRARIES(picotls-esni picotls-openssl picotls-core ${OPENSSL_LIBRARIES} ${CMAKE_DL_LIBS})
    ADD_EXECUTABLE(test-openssl.t ${MINICRYPTO_LIBRARY_FILES} lib/cifra.c lib/uecc.c lib/asn1.c lib/pembase64.c lib/ffx.c deps/picotest/picotest.c t/picotls.c t/openssl.c)
    SET_TARGET_PROPERTIES(test-openssl.t PROPERTIES COMPILE_FLAGS "-DPTLS_MEMORY_DEBUG=1")
    TARGET_LINK_LIBRARIES(test-openssl.t ${OPENSSL_LIBRARIES} ${CMAKE_DL_LIBS})
    SET(TEST_EXES ${TEST_EXES} test-openssl.t)
ELSE ()
    MESSAGE(WARNING "Disabling OpenSSL support (requires 1.0.1 or newer)")
ENDIF ()

ADD_CUSTOM_TARGET(check env BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR} prove --exec '' -v ${CMAKE_CURRENT_BINARY_DIR}/*.t t/*.t WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} DEPENDS ${TEST_EXES} cli)

IF (CMAKE_SYSTEM_NAME STREQUAL "Linux")
     SET(CMAKE_C_FLAGS "-D_GNU_SOURCE -pthread ${CMAKE_C_FLAGS}")
ELSEIF ("${CMAKE_SYSTEM_NAME}" MATCHES "SunOS")
    TARGET_LINK_LIBRARIES(cli "socket" "nsl")
ENDIF ()

IF (BUILD_FUZZER)
    IF (NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        MESSAGE(FATAL ERROR "The fuzzer needs clang as a compiler")
    ENDIF()

    ADD_EXECUTABLE(fuzzer-asn1-validation fuzz/fuzzer-asn1-validation.c lib/asn1.c)
    SET_TARGET_PROPERTIES(fuzzer-asn1-validation PROPERTIES LINK_FLAGS "-fsanitize=fuzzer")
    SET_TARGET_PROPERTIES(fuzzer-asn1-validation PROPERTIES COMPILE_FLAGS "-fsanitize=fuzzer")

    ADD_EXECUTABLE(fuzzer-asn1-type-and-length fuzz/fuzzer-asn1-type-and-length.c lib/asn1.c)
    SET_TARGET_PROPERTIES(fuzzer-asn1-type-and-length PROPERTIES LINK_FLAGS "-fsanitize=fuzzer")
    SET_TARGET_PROPERTIES(fuzzer-asn1-type-and-length PROPERTIES COMPILE_FLAGS "-fsanitize=fuzzer")

    SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_GNU_SOURCE")
    INCLUDE_DIRECTORIES(t include ${OPENSSL_INCLUDE_DIR})
    ADD_DEFINITIONS(-DPTLS_FUZZ_HANDSHAKE=1)

    ADD_EXECUTABLE(fuzz-server-hello fuzz/fuzz-server-hello.c)
    SET_TARGET_PROPERTIES(fuzz-server-hello PROPERTIES LINK_FLAGS "-fsanitize=fuzzer")
    SET_TARGET_PROPERTIES(fuzz-server-hello PROPERTIES COMPILE_FLAGS "-fsanitize=fuzzer")
    TARGET_LINK_LIBRARIES(fuzz-server-hello ${OPENSSL_LIBRARIES} picotls-core picotls-openssl)

    ADD_EXECUTABLE(fuzz-client-hello fuzz/fuzz-client-hello.c)
    SET_TARGET_PROPERTIES(fuzz-client-hello PROPERTIES LINK_FLAGS "-fsanitize=fuzzer")
    SET_TARGET_PROPERTIES(fuzz-client-hello PROPERTIES COMPILE_FLAGS "-fsanitize=fuzzer")
    TARGET_LINK_LIBRARIES(fuzz-client-hello ${OPENSSL_LIBRARIES} picotls-core picotls-openssl)


ENDIF()
