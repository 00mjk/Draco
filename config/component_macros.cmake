#--------------------------------------------*-cmake-*---------------------------------------------#
# file   config/component_macros.cmake
# author Kelly G. Thompson, kgt@lanl.gov
# date   2010 Dec 1
# brief  Provide extra macros to simplify CMakeLists.txt for component directories.
# note   Copyright (C) 2016-2020 Triad National Security, LLC., All rights reserved.
#--------------------------------------------------------------------------------------------------#

include_guard(GLOBAL)
include( compilerEnv )

#--------------------------------------------------------------------------------------------------#
# Ensure order of setup is correct
#--------------------------------------------------------------------------------------------------#
if( NOT DEFINED USE_IPO )
  dbsSetupCompilers() # sets USE_IPO
endif()

#--------------------------------------------------------------------------------------------------#
# Common Standards
#--------------------------------------------------------------------------------------------------#

# Apply these properties to all targets (libraries, executables)
set(Draco_std_target_props_C
  C_STANDARD 11                # Force strict ANSI-C 11 standard
  C_EXTENSIONS OFF
  C_STANDARD_REQUIRED ON )
set(Draco_std_target_props_CXX
  CXX_STANDARD 14              # Force strict C++ 14 standard
  CXX_EXTENSIONS OFF
  CXX_STANDARD_REQUIRED ON )
set(Draco_std_target_props_CUDA
  CUDA_STANDARD 14              # Force strict C++ 14 standard
  CUDA_EXTENSIONS OFF
  CUDA_STANDARD_REQUIRED ON)
#  CUDA_SEPARABLE_COMPILATION ON)
#  CUDA_RESOLVE_DEVICE_SYMBOLS ON )
# target_include_directories (my lib
#     PUBLIC $<BUILD_INTERFACE:${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES}> )
set(Draco_std_target_props
  INTERPROCEDURAL_OPTIMIZATION_RELEASE ${USE_IPO}
  POSITION_INDEPENDENT_CODE ON )

#--------------------------------------------------------------------------------------------------#
# Set properties that are common across all packages.  Including the required language standard per
# target.
#--------------------------------------------------------------------------------------------------#
function( dbs_std_tgt_props target )

  get_property(project_enabled_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
  foreach( lang ${project_enabled_languages} )
    if( ${lang} STREQUAL "C" )
      set_target_properties( ${target} PROPERTIES ${Draco_std_target_props_C} )
    elseif( ${lang} STREQUAL "CXX" )
      set_target_properties( ${target}
        PROPERTIES ${Draco_std_target_props_CXX} )
    elseif( ${lang} STREQUAL "CUDA" )
      set_target_properties( ${target}
        PROPERTIES ${Draco_std_target_props_CUDA} )
    endif()
    set_target_properties( ${target} PROPERTIES ${Draco_std_target_props} )
  endforeach()

  # Helper for clang-tidy that points to very old gcc STL files.  We need STL
  # files from clang (at least for llvm-6.  llvm-9 doesn't need this and it
  # actually causes issues).
  if( "${DRACO_STATIC_ANALYZER}" MATCHES "clang-tidy" AND
      CMAKE_CXX_COMPILER_VERSION VERSION_LESS 9.0 )
    if( NOT CLANG_TIDY_IPATH )
      message(FATAL_ERROR "Unable to configure clang-tidy build because"
        " CLANG_TIDY_IPATH is empty.")
    endif()
    get_target_property( tgt_sources ${target} SOURCES )
    set_source_files_properties( ${tgt_sources} PROPERTIES INCLUDE_DIRECTORIES
      ${CLANG_TIDY_IPATH} )
  endif()

endfunction()

#--------------------------------------------------------------------------------------------------#
# Build a list of dependencies to support object-library mechanism
#
# objlib_target - object library target name (e.g. Objlib_c4)
#
# Returns ${objlib_target}_TARGET_DEPS by saving it to the CMakeCache.txt
#--------------------------------------------------------------------------------------------------#
function( dbs_objlib_build_dep_list objlib_target deplist)

  set(itd_beg 0 ) # length of dep list
  list(LENGTH deplist itd_end)
  while( NOT ${itd_beg} STREQUAL ${itd_end} )
    foreach(dep ${deplist} )
      if(NOT "${${dep}_TARGET_DEPS}x" STREQUAL "x")
        list(APPEND deplist ${${dep}_TARGET_DEPS} )
      endif()
      get_target_property(ill ${dep} INTERFACE_LINK_LIBRARIES )
      if(NOT ill MATCHES NOTFOUND)
        foreach( i ${ill} )
          if( TARGET ${i} )
            list(APPEND deplist ${i} )
          endif()
        endforeach()
      endif()
    endforeach()
    list(REMOVE_DUPLICATES deplist)
    set( itd_beg ${itd_end} )
    list(LENGTH deplist itd_end)
  endwhile()
  set( ${objlib_target}_TARGET_DEPS "${deplist}" CACHE STRING "objlib dependencies" FORCE)

endfunction()

#--------------------------------------------------------------------------------------------------#
# replacement for built in command 'add_executable'
#
# Purpose 1: In addition to adding an executable built from $sources, set Draco-specific properties
# for the library.  This macro reduces ~20 lines of code repeated code down to 1-2.
#
# Purpose 2: Encapsulate library and vendor library dependencies per package.
#
# Purpose 3: Use information from 1 and 2 above to generate exported targets.
#
# Usage:
#
# add_component_executable(
#   TARGET       "target name"
#   EXE_NAME     "output executable name"
#   TARGET_DEPS  "dep1;dep2;..."
#   SOURCES      "file1.cc;file2.cc;..."
#   HEADERS      "file1.hh;file2.hh;..."
#   VENDOR_LIST  "MPI;GSL"
#   VENDOR_LIBS  "${MPI_CXX_LIBRARIES};${GSL_LIBRARIES}"
#   VENDOR_INCLUDE_DIRS "${MPI_CXX_INCLUDE_DIR};${GSL_INCLUDE_DIR}"
#   FOLDER       "myfolder"
#   PROJECT_LABEL "myproject42"
#   NOEXPORT    - do not export target or dependencies to draco-config.cmake
#   EXPORT_NAME - not currently used; but will be used to install a binary and add its information
#                 to <project>-config.cmake.
#   NOCOMMANDWINDOW - On win32, do not create a command window (qt)
#   )
#
# Example:
#
# add_component_executable(
#   TARGET       Exe_draco_info
#   EXE_NAME     draco_info
#   TARGET_DEPS  Lib_diagnostics
#   SOURCES      "${PROJECT_SOURCE_DIR}/draco_info_main.cc"
#   FOLDER       diagnostics
#   )
#
# Note: directories listed as VENDOR_INCLUDE_DIRS will be exported in the
#       INTERFACE_INCLUDE_DIRECTORIES target property.
#
#--------------------------------------------------------------------------------------------------#
macro( add_component_executable )

  # These become variables of the form ${ace_NAME}, etc.
  cmake_parse_arguments(
    ace
    "NOEXPORT;NOCOMMANDWINDOW"
    "EXPORT_NAME;TARGET;EXE_NAME;LINK_LANGUAGE;FOLDER;PROJECT_LABEL"
    "HEADERS;SOURCES;TARGET_DEPS;VENDOR_LIST;VENDOR_LIBS;VENDOR_INCLUDE_DIRS"
    ${ARGV}
    )

  # Default link language is C++
  if( NOT DEFINED ace_LINK_LANGUAGE )
    set( ace_LINK_LANGUAGE CXX )
  endif()

  #
  # Add headers to Visual Studio or Xcode solutions
  #
  if( ace_HEADERS )
    if( MSVC_IDE OR ${CMAKE_GENERATOR} MATCHES Xcode )
      list( APPEND ace_SOURCES ${ace_HEADERS} )
    endif()
  endif()

  if( NOT DEFINED ace_EXE_NAME )
    string( REPLACE "Exe_" "" ace_EXE_NAME ${ace_TARGET} )
  endif()

  #
  # Create the library and set the properties
  #

  # Set the component name: If registered from a test directory, extract
  # the parent's name.
  get_filename_component( ldir ${CMAKE_CURRENT_SOURCE_DIR} NAME )
  if( ${ldir} STREQUAL "test")
    get_filename_component( comp_target ${CMAKE_CURRENT_SOURCE_DIR} DIRECTORY )
    get_filename_component( comp_target ${comp_target} NAME )
    set( comp_target ${comp_target}_test )
  elseif( ${ldir} STREQUAL "bin" )
    get_filename_component( comp_target ${CMAKE_CURRENT_SOURCE_DIR} DIRECTORY )
    get_filename_component( comp_target ${comp_target} NAME )
  else()
    get_filename_component( comp_target ${CMAKE_CURRENT_SOURCE_DIR} NAME )
  endif()
  # Make the name safe: replace + with x
  string( REGEX REPLACE "[+]" "x" comp_target ${comp_target} )
  # Set the folder name:
  if( NOT DEFINED ace_FOLDER )
    set( ace_FOLDER ${comp_target} )
  endif()

  if( WIN32 AND ace_NOCOMMANDWINDOW )
    # The Win32 option prevents the command console from activating while the GUI is running.
    add_executable( ${ace_TARGET} WIN32 ${ace_SOURCES} )
  else()
    add_executable( ${ace_TARGET} ${ace_SOURCES} )
  endif()
  dbs_std_tgt_props( ${ace_TARGET} )
  set_target_properties( ${ace_TARGET} PROPERTIES
    OUTPUT_NAME ${ace_EXE_NAME}
    FOLDER      ${ace_FOLDER}
    COMPILE_DEFINITIONS "PROJECT_SOURCE_DIR=\"${PROJECT_SOURCE_DIR}\";PROJECT_BINARY_DIR=\"${PROJECT_BINARY_DIR}\"" )
  if( DEFINED ace_PROJECT_LABEL )
    set_target_properties( ${ace_TARGET} PROPERTIES PROJECT_LABEL ${ace_PROJECT_LABEL} )
  endif()

  #
  # Generate properties related to library dependencies
  #
  if( DEFINED ace_TARGET_DEPS )
    if(DBS_GENERATE_OBJECT_LIBRARIES)
      unset( ace_objlib_TARGET_DEPS )
      foreach( lib ${ace_TARGET_DEPS} )
        string( REPLACE "Lib_" "Objlib_" objlib ${lib} )
        if( TARGET ${objlib} )
          list(APPEND ace_objlib_TARGET_DEPS ${objlib} )
        else()
          list(APPEND ace_objlib_TARGET_DEPS ${lib} )
        endif()
      endforeach()
      # Keep a list of transitive dependencies; returns ${ace_objlib_TARGET}_TARGET_DEPS
      dbs_objlib_build_dep_list(${ace_TARGET} "${ace_objlib_TARGET_DEPS}")
      target_link_libraries( ${ace_TARGET} ${${ace_TARGET}_TARGET_DEPS} )
    else()
      target_link_libraries( ${ace_TARGET} ${ace_TARGET_DEPS} )
    endif()
  endif()
  if( DEFINED ace_VENDOR_LIBS )
    target_link_libraries( ${ace_TARGET} ${ace_VENDOR_LIBS} )
  endif()
  if( ace_VENDOR_INCLUDE_DIRS )
    set_property(TARGET ${ace_TARGET} APPEND PROPERTY
      INTERFACE_INCLUDE_DIRECTORIES "${ace_VENDOR_INCLUDE_DIRS}")
  endif()

endmacro()

#------------------------------------------------------------------------------
# replacement for built in command 'add_library'
#
# Purpose 1: In addition to adding a library built from $sources, set
# Draco-specific properties for the library.  This macro reduces ~20
# lines of code down to 1-2.
#
# Purpose 2: Encapsulate library and vendor library dependencies per
# package.
#
# Purpose 3: Use information from 1 and 2 above to generate exported
# targets.
#
# Usage:
#
# add_component_library(
#   TARGET       "target name"
#   LIBRARY_NAME "output library name"
#   TARGET_DEPS  "dep1;dep2;..."
#   INCLUDE_DIRS "PUBLIC;$<BUILD_INTERFACE:${PROJECT_BINARY_DIR}>"
#   SOURCES      "file1.cc;file2.cc;..."
#   HEADERS      "file1.hh;file2.hh;..."
#   LIBRARY_NAME_PREFIX "rtt_"
#   LIBRARY_TYPE "SHARED"
#   VENDOR_LIST  "MPI;GSL"
#   VENDOR_LIBS  "${MPI_CXX_LIBRARIES};${GSL_LIBRARIES}"
#   VENDOR_INCLUDE_DIRS "${MPI_CXX_INCLUDE_DIR};${GSL_INCLUDE_DIR}"
#   NOEXPORT
#   )
#
# Example:
#
# add_component_library(
#   TARGET       Lib_quadrature
#   LIBRARY_NAME quadrature
#   TARGET_DEPS  "Lib_parser;Lib_special_functions;Lib_mesh_element"
#   SOURCES      "${sources}"
#   )
#
# Note: directories listed as VENDOR_INCLUDE_DIRS will be exported in the
#       INTERFACE_INCLUDE_DIRECTORIES target property.
#
# Note: you must use quotes around ${list_of_sources} to preserve the list.
#------------------------------------------------------------------------------
macro( add_component_library )

  # These become variables of the form ${acl_NAME}, etc.
  cmake_parse_arguments(
    acl
    "NOEXPORT"
    "EXPORT_NAME;TARGET;LIBRARY_NAME;LIBRARY_NAME_PREFIX;LIBRARY_TYPE;LINK_LANGUAGE"
    "HEADERS;SOURCES;INCLUDE_DIRS;TARGET_DEPS;VENDOR_LIST;VENDOR_LIBS;VENDOR_INCLUDE_DIRS"
    ${ARGV} )

  #
  # Defaults:
  #
  # Optional 3rd argument is the library prefix.  The default is "rtt_".
  if( NOT acl_LIBRARY_NAME_PREFIX )
    set( acl_LIBRARY_NAME_PREFIX "rtt_" )
  endif()
  # Default link language is C++
  if( NOT acl_LINK_LANGUAGE )
    set( acl_LINK_LANGUAGE CXX )
  endif()
  if( "${acl_LINK_LANGUAGE}" STREQUAL "CUDA" )
    set_property( SOURCE ${acl_SOURCES} APPEND PROPERTY LANGUAGE CUDA )
    set( acl_LIBRARY_TYPE STATIC )
  endif()

  #
  # Add headers to Visual Studio or Xcode solutions
  #
  if( acl_HEADERS )
    if( MSVC_IDE OR "${CMAKE_GENERATOR}" MATCHES Xcode )
      list( APPEND acl_SOURCES ${acl_HEADERS} )
    endif()
  endif()

  # if a library type was not specified use the default Draco setting
  if(NOT acl_LIBRARY_TYPE)
    set( acl_LIBRARY_TYPE ${DRACO_LIBRARY_TYPE})
  endif()

  #
  # Create the library and set the properties
  #

  # If this is a test library.  Find the component name
  string( REPLACE "_test" "" comp_target ${acl_TARGET} )
  # extract project name, minus leading "Lib_"
  string( REPLACE "Lib_" "" folder_name ${acl_TARGET} )

  add_library( ${acl_TARGET} ${acl_LIBRARY_TYPE} ${acl_SOURCES} )
  dbs_std_tgt_props( ${acl_TARGET} )
  set_target_properties( ${acl_TARGET} PROPERTIES
    OUTPUT_NAME ${acl_LIBRARY_NAME_PREFIX}${acl_LIBRARY_NAME}
    FOLDER      ${folder_name}
    WINDOWS_EXPORT_ALL_SYMBOLS ON )
  if( DEFINED DRACO_LINK_OPTIONS AND NOT "${DRACO_LINK_OPTIONS}x" STREQUAL "x")
    set_property( TARGET ${acl_TARGET} APPEND PROPERTY
      LINK_OPTIONS ${DRACO_LINK_OPTIONS} )
  endif()

  if(DBS_GENERATE_OBJECT_LIBRARIES)
    # Generate an object library.  This can be used instead of the regular library for better
    # interprocedural optimization at link time.
    if( "${acl_TARGET}" MATCHES "Lib_" )
      string( REPLACE "Lib_" "Objlib_" acl_objlib_TARGET ${acl_TARGET} )
    else()
      string( CONCAT acl_objlib_TARGET "Objlib_" "${acl_TARGET}" )
    endif()
    if( DEFINED acl_SOURCES )
      add_library( ${acl_objlib_TARGET} OBJECT ${acl_SOURCES} )
    else()
      message(FATAL_ERROR "acl_sources NOT defined")
    endif()
  endif()

  #
  # Generate properties related to library dependencies
  #
  if( DEFINED acl_TARGET_DEPS )
    target_link_libraries( ${acl_TARGET} ${acl_TARGET_DEPS} )
    if(DBS_GENERATE_OBJECT_LIBRARIES)
      unset( acl_objlib_TARGET_DEPS )
      foreach( lib ${acl_TARGET_DEPS} )
        string( REPLACE "Lib_" "Objlib_" objlib ${lib} )
        if( TARGET ${objlib} )
          list(APPEND acl_objlib_TARGET_DEPS ${objlib} )
        else()
          list(APPEND acl_objlib_TARGET_DEPS ${lib} )
        endif()
      endforeach()
      # Keep a list of transitive dependencies; returns ${acl_objlib_TARGET}_TARGET_DEPS
      dbs_objlib_build_dep_list(${acl_objlib_TARGET} "${acl_objlib_TARGET_DEPS}")

      # Create the actual dependency.
      target_link_libraries( ${acl_objlib_TARGET} ${${acl_objlib_TARGET}_TARGET_DEPS} )
    else()
      target_link_libraries( ${acl_TARGET} ${acl_TARGET_DEPS} )
    endif()
  endif()
  if( DEFINED acl_INCLUDE_DIRS )
    target_include_directories( ${acl_TARGET} ${acl_INCLUDE_DIRS} )
    if(DBS_GENERATE_OBJECT_LIBRARIES)
      target_include_directories( ${acl_objlib_TARGET} ${acl_INCLUDE_DIRS} )
    endif()
  endif()
  if( NOT "${acl_VENDOR_LIBS}x" STREQUAL "x" )
    target_link_libraries( ${acl_TARGET} ${acl_VENDOR_LIBS} )
  endif()
  if( acl_VENDOR_INCLUDE_DIRS )
    set_property(TARGET ${acl_TARGET} APPEND PROPERTY
      INTERFACE_INCLUDE_DIRECTORIES "${acl_VENDOR_INCLUDE_DIRS}")
  endif()

  #
  # Basic install commands for the library or object-library that are common to all Draco packages.
  #
  if( acl_NOEXPORT )
    # if package is marked as NOEXPRT, we do not create an installation instruction.
  else()
    if( NOT DEFINED acl_EXPORT_NAME )
      set(acl_EXPORT_NAME "draco-targets")  # default value.
    endif()
    install( TARGETS ${acl_TARGET} EXPORT ${acl_EXPORT_NAME} DESTINATION ${DBSCFGDIR}lib )
    if(DBS_GENERATE_OBJECT_LIBRARIES)
      install( TARGETS ${acl_objlib_TARGET} EXPORT ${acl_EXPORT_NAME} DESTINATION ${DBSCFGDIR}lib )
    endif()
  endif()
  if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    install(FILES $<TARGET_PDB_FILE:${acl_TARGET}> DESTINATION ${DBSCFGDIR}lib OPTIONAL)
  endif()

endmacro()

# ------------------------------------------------------------
# Register_scalar_test()
#
# 1. Special treatment for Roadrunner/ppe code (must ssh and then run)
# 2. Register the test
# 3. Register the pass/fail criteria.
# ------------------------------------------------------------
macro( register_scalar_test targetname runcmd command cmd_args )

  separate_arguments( cmdargs UNIX_COMMAND ${cmd_args} )

  set(lverbose OFF)
  if( lverbose)
    message("add_test( NAME ${targetname} COMMAND ${RUN_CMD} ${command} ${cmdargs} )")
  endif()
  add_test( NAME ${targetname} COMMAND ${RUN_CMD} ${command} ${cmdargs} )

  # Reserve enough threads for application unit tests. Normally we only need 1
  # core for each scalar test.
  set( num_procs 1 )

  # For application unit tests, a parallel job is forked that needs more cores.
  if( addscalartest_APPLICATION_UNIT_TEST )
    if( "${cmd_args}" MATCHES "--np" AND NOT "${cmd_args}" MATCHES "scalar")
      string( REGEX REPLACE "--np ([0-9]+)" "\\1" num_procs "${cmd_args}" )
      # the forked processes needs $num_proc threads.  add one for the master
      # thread, the original scalar process.
      math( EXPR num_procs  "${num_procs} + 1" )
    endif()
  endif()

  # set pass fail criteria, processors required, etc.
  set_tests_properties( ${targetname}
    PROPERTIES
    PASS_REGULAR_EXPRESSION "${addscalartest_PASS_REGEX}"
    FAIL_REGULAR_EXPRESSION "${addscalartest_FAIL_REGEX}"
    PROCESSORS              "${num_procs}"
    WORKING_DIRECTORY       "${PROJECT_BINARY_DIR}"
    )
  if( NOT "${addscalartest_RESOURCE_LOCK}none" STREQUAL "none" )
    set_tests_properties( ${targetname}
      PROPERTIES RESOURCE_LOCK "${addscalartest_RESOURCE_LOCK}" )
  endif()
  if( NOT "${addscalartest_RUN_AFTER}none" STREQUAL "none" )
    set_tests_properties( ${targetname}
      PROPERTIES DEPENDS "${addscalartest_RUN_AFTER}" )
  endif()

  # Labels
  # message("LABEL (ast) = ${addscalartest_LABEL}")
  if( NOT "${addscalartest_LABEL}x" STREQUAL "x" )
    set_tests_properties( ${targetname}
      PROPERTIES  LABELS "${addscalartest_LABEL}" )
  endif()
  unset( num_procs )
  unset( lverbose )
endmacro()

# ------------------------------------------------------------
# Register_parallel_test()
#
# 1. Register the test
# 2. Register the pass/fail criteria.
# ------------------------------------------------------------
macro( register_parallel_test targetname numPE command cmd_args )
  set( lverbose OFF )
  if( lverbose )
    message( "      Adding test: ${targetname}" )
  endif()
  unset( RUN_CMD )

  if( addparalleltest_MPI_PLUS_OMP )
    string( REPLACE " " ";" mpiexec_omp_preflags_list "${MPIEXEC_OMP_PREFLAGS}" )
    add_test(
      NAME    ${targetname}
      COMMAND ${RUN_CMD} ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} ${numPE}
              ${mpiexec_omp_preflags_list}
              ${command}
              ${cmdarg}
              )
  else()
    add_test(
      NAME    ${targetname}
      COMMAND ${RUN_CMD} ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} ${numPE}
              ${MPIRUN_PREFLAGS}
              ${command}
              ${cmdarg}
              )
  endif()
  set_tests_properties( ${targetname}
    PROPERTIES
    PASS_REGULAR_EXPRESSION "${addparalleltest_PASS_REGEX}"
    FAIL_REGULAR_EXPRESSION "${addparalleltest_FAIL_REGEX}"
    WORKING_DIRECTORY       "${PROJECT_BINARY_DIR}"
    )
  if( NOT "${addparalleltest_RESOURCE_LOCK}none" STREQUAL "none" )
    set_tests_properties( ${targetname}
      PROPERTIES RESOURCE_LOCK "${addparalleltest_RESOURCE_LOCK}" )
  endif()
  if( NOT "${addparalleltest_RUN_AFTER}none" STREQUAL "none" )
    set_tests_properties( ${targetname}
      PROPERTIES DEPENDS "${addparalleltest_RUN_AFTER}" )
  endif()

  if( addparalleltest_MPI_PLUS_OMP )

    if( DEFINED ENV{OMP_NUM_THREADS} )
      math( EXPR numthreads "${numPE} * $ENV{OMP_NUM_THREADS}" )
    else()
      math( EXPR numthreads "${numPE} * ${MPI_CORES_PER_CPU}" )
    endif()

    if( MPI_HYPERTHREADING )
      math( EXPR numthreads "2 * ${numthreads}" )
    endif()
    set_tests_properties( ${targetname}
      PROPERTIES
        PROCESSORS "${numthreads}"
        LABELS     "nomemcheck" )
    unset( numthreads )
    unset( nnodes )
    unset( nnodes_remainder )

  else()

    if( DEFINED addparalleltest_LABEL )
      set_tests_properties( ${targetname}
          PROPERTIES LABELS "${addparalleltest_LABEL}" )
    endif()
    set_tests_properties( ${targetname} PROPERTIES PROCESSORS "${numPE}" )

  endif()
  unset( lverbose )
endmacro()

#--------------------------------------------------------------------------------------------------#
# add_scalar_tests
#
# Given a list of sources, create unit test executables, one exe for each source file.  Register the
# test to be run by ctest.
#
# Usage:
#
# add_scalar_tests(
#    SOURCES "${test_sources}"
#    [ DEPS    "${library_dependencies}" ]
#    [ TEST_ARGS     "arg1;arg2" ]
#    [ PASS_REGEX    "regex" ]
#    [ FAIL_REGEX    "regex" ]
#    [ RESOURCE_LOCK "lockname" ]
#    [ RUN_AFTER     "test_name" ]
#    [ APPLICATION_UNIT_TEST ]
# )
#
# Options:
#   APPLICATION_UNIT_TEST - (CI/CT only) If present, do not run the test under 'aprun'.
#        ApplicationUnitTest based tests must be run this way.  Setting this option when
#        DRACO_C4==SCALAR will reset any value provided in TEST_ARGS to be "--np scalar".
#   LINK_WITH_FORTRAN - Tell the compiler to use the Fortran compiler for the final link of the
#        test.  This is needed for Intel and PGI.
#
#--------------------------------------------------------------------------------------------------#
macro( add_scalar_tests test_sources )

  # These become variables of the form ${addscalartests_SOURCES}, etc.
  cmake_parse_arguments(
    addscalartest
    "APPLICATION_UNIT_TEST;LINK_WITH_FORTRAN;NONE"
    "LABEL;LINK_LANGUAGE"
    "DEPS;FAIL_REGEX;PASS_REGEX;RESOURCE_LOCK;RUN_AFTER;SOURCES;TEST_ARGS"
    ${ARGV} )

  # Sanity Checks
  # ------------------------------------------------------------
  if( "${addscalartest_SOURCES}none" STREQUAL "none" )
    message( FATAL_ERROR "You must provide the keyword SOURCES and a list of "
      "sources when using the add_scalar_tests macro.  Please see "
      "draco/config/component_macros.cmake::add_scalar_tests() for more "
      "information." )
  endif()

  # Defaults:
  # ------------------------------------------------------------

  # Default link language is C++
  if( NOT addscalartest_LINK_LANGUAGE )
    set( addscalartest_LINK_LANGUAGE CXX )
  endif()
 if( "${addscalartest_LINK_LANGUAGE}" STREQUAL "CUDA" )
   set_source_files_properties( ${addscalartest_SOURCES} PROPERTIES LANGUAGE CUDA )
 endif()

  # Special Cases:
  # ------------------------------------------------------------
  # On some platforms (Trinity, Sierra), even scalar tests must be run
  # underneath MPIEXEC_EXECUTABLE (srun, jsrun, lrun):
  separate_arguments(MPIEXEC_PREFLAGS)
  if( "${MPIEXEC_EXECUTABLE}" MATCHES "srun" OR
      "${MPIEXEC_EXECUTABLE}" MATCHES "jsrun" )
    set( RUN_CMD ${MPIEXEC_EXECUTABLE} ${MPIEXEC_PREFLAGS} ${MPIEXEC_NUMPROC_FLAG} 1 )
  else()
    unset( RUN_CMD )
  endif()

  # Special cases for tests that use the ApplicationUnitTest
  # framework (see c4/ApplicationUnitTest.hh).
  if( addscalartest_APPLICATION_UNIT_TEST )
    # If this is an ApplicationUnitTest based test then the TEST_ARGS will look
    # like "--np 1;--np 2;--np 4".  For the case where DRACO_C4 = SCALAR, we
    # will automatically demote these arguments to "--np scalar."
    if( "${DRACO_C4}" MATCHES "SCALAR" )
      set( addscalartest_TEST_ARGS "--np scalar" )
    endif()

  endif()

  # Pass/Fail criteria
  if( "${addscalartest_PASS_REGEX}none" STREQUAL "none" )
    set( addscalartest_PASS_REGEX ".*[Tt]est: PASSED" )
  endif()
  if( "${addscalartest_FAIL_REGEX}none" STREQUAL "none" )
    set( addscalartest_FAIL_REGEX ".*[Tt]est: FAILED" )
    list( APPEND addscalartest_FAIL_REGEX ".*ERROR:.*" )
    list( APPEND addscalartest_FAIL_REGEX "forrtl: error" )
  endif()

  # Format resource lock command
  if( NOT "${addscalartest_RESOURCE_LOCK}none" STREQUAL "none" )
    set( addscalartest_RESOURCE_LOCK
      "RESOURCE_LOCK ${addscalartest_RESOURCE_LOCK}")
  endif()

  # What is the component name (always use Lib_${compname} as a dependency).
  string( REPLACE "_test" "" compname ${PROJECT_NAME} )
  string( REPLACE "_ftest" "" compname ${compname} )
  string( REPLACE "_cudatest" "" compname ${compname} )

  # Loop over each test source files:
  # 1. Compile the executable
  # 2. Register the unit test

  # Generate the executable
  # ------------------------------------------------------------
  foreach( file ${addscalartest_SOURCES} )

    get_filename_component( testname ${file} NAME_WE )
    add_executable( Ut_${compname}_${testname}_exe ${file} )
    dbs_std_tgt_props( Ut_${compname}_${testname}_exe )
    set_property( TARGET Ut_${compname}_${testname}_exe APPEND PROPERTY
      OUTPUT_NAME ${testname} )
    set_property( TARGET Ut_${compname}_${testname}_exe APPEND PROPERTY
      VS_KEYWORD  ${testname} )
    set_property( TARGET Ut_${compname}_${testname}_exe APPEND PROPERTY
      FOLDER      ${compname}_test )
    set_property( TARGET Ut_${compname}_${testname}_exe APPEND PROPERTY
      COMPILE_DEFINITIONS "PROJECT_SOURCE_DIR=\"${PROJECT_SOURCE_DIR}\"" )
    set_property( TARGET Ut_${compname}_${testname}_exe APPEND PROPERTY
      COMPILE_DEFINITIONS "PROJECT_BINARY_DIR=\"${PROJECT_BINARY_DIR}\"" )
    if( DEFINED DRACO_LINK_OPTIONS AND
        NOT "${DRACO_LINK_OPTIONS}x" STREQUAL "x")
      set_property( TARGET Ut_${compname}_${testname}_exe APPEND PROPERTY
        LINK_OPTIONS ${DRACO_LINK_OPTIONS} )
    endif()
    if( addscalartest_LINK_WITH_FORTRAN )
      set_property( TARGET Ut_${compname}_${testname}_exe APPEND
        PROPERTY LINKER_LANGUAGE Fortran )
    endif()
    target_link_libraries(
      Ut_${compname}_${testname}_exe
      ${test_lib_target_name}
      ${addscalartest_DEPS} )
  endforeach()

  # Register the unit test
  # ------------------------------------------------------------
  foreach( file ${addscalartest_SOURCES} )
    get_filename_component( testname ${file} NAME_WE )

    if( "${addscalartest_TEST_ARGS}none" STREQUAL "none" )
      register_scalar_test( ${compname}_${testname}
        "${RUN_CMD}" $<TARGET_FILE:Ut_${compname}_${testname}_exe> "" )
    else()
      set( iarg "0" )
      foreach( cmdarg ${addscalartest_TEST_ARGS} )
        math( EXPR iarg "${iarg} + 1" )
        register_scalar_test( ${compname}_${testname}_arg${iarg}
          "${RUN_CMD}" $<TARGET_FILE:Ut_${compname}_${testname}_exe> "${cmdarg}" )
      endforeach()
    endif()
  endforeach()

endmacro(add_scalar_tests)

#----------------------------------------------------------------------#
# add_parallel_tests
#
# Given a list of sources, create unit test executables, one exe for
# each source file.  Register the test to be run by ctest.
#
# Usage:
#
# add_parallel_tests(
#    SOURCES "${test_sources}"
#    DEPS    "${library_dependencies}"
#    PE_LIST "1;2;4" )
#
# Optional parameters that require arguments.
#
#    SOURCES         - semi-colon delimited list of files.
#    PE_LIST         - semi-colon delimited list of integers (number of MPI
#                      ranks).
#    DEPS            - CMake target dependencies.
#    TEST_ARGS       - Command line arguments to use when running the test.
#    PASS_REGEX      - This regex must exist in the output to produce
#                      a 'pass.'
#    FAIL_REGEX      - If this regex exists in the output, the test
#                      will 'fail.'
#    RESOURCE_LOCK   - Tests with this common string identifier will
#                      not be run concurrently.
#    RUN_AFTER       - The argument to this option is a test name that
#                      must complete before the current test will be
#                      allowed to run
#    MPIFLAGS
#    LABEL           - Label that can be used to select tests via
#                      ctest's -R or -E options.
#
# Optional parameters that require arguments.
#
#    MPI_PLUS_OMP    - This bool indicates that the test uses OpenMP
#                      for each MPI rank.
#    LINK_WITH_FORTRAN - Use the Fortran compiler to perform the final
#                      link of the unit test.
#----------------------------------------------------------------------#
macro( add_parallel_tests )

  cmake_parse_arguments(
    addparalleltest
    "MPI_PLUS_OMP;LINK_WITH_FORTRAN"
    "LABEL"
    "DEPS;FAIL_REGEX;MPIFLAGS;PASS_REGEX;PE_LIST;RESOURCE_LOCK;RUN_AFTER;SOURCES;TEST_ARGS"
    ${ARGV}
    )

  set(lverbose OFF)

  # Sanity Check
  if( "${addparalleltest_SOURCES}none" STREQUAL "none" )
    message( FATAL_ERROR "You must provide the keyword SOURCES and a list of sources when using the add_parallel_tests macro.  Please see draco/config/component_macros.cmake::add_parallel_tests() for more information." )
  endif()
  if( "${addparalleltest_PE_LIST}none" STREQUAL "none" )
    message( FATAL_ERROR "You must provide the keyword PE_LIST and a list containing the number of cores used to execute this test (e.g. \"PE_LIST  \"1;2;4\"\").  Please see draco/config/component_macros.cmake::add_parallel_tests() for more information." )
  endif()


  # Pass/Fail criteria
  if( "${addparalleltest_PASS_REGEX}none" STREQUAL "none" )
    set( addparalleltest_PASS_REGEX ".*[Tt]est: PASSED" )
  endif()
  if( "${addparalleltest_FAIL_REGEX}none" STREQUAL "none" )
    set( addparalleltest_FAIL_REGEX ".*[Tt]est: FAILED" )
    list( APPEND addparalleltest_FAIL_REGEX ".*ERROR:.*" )
    list( APPEND addparalleltest_FAIL_REGEX "forrtl: error" )
  endif()

  # Format resource lock command
  if( NOT "${addparalleltest_RESOURCE_LOCK}none" STREQUAL "none" )
    set( addparalleltest_RESOURCE_LOCK
      "RESOURCE_LOCK ${addparalleltest_RESOURCE_LOCK}")
  endif()

  # What is the component name? Use this to give a target name to the test.
  string( REPLACE "_test" "" compname ${PROJECT_NAME} )

  # Override MPI Flags upon user request
  if ( NOT DEFINED addparalleltest_MPIFLAGS )
    set( MPIRUN_PREFLAGS ${MPIEXEC_PREFLAGS} )
  else()
    set( MPIRUN_PREFLAGS "${addparalleltest_MPIFLAGS}" )
  endif()
  separate_arguments( MPIRUN_PREFLAGS )

  # Loop over each test source files:
  # 1. Compile the executable
  # 2. Link against dependencies (libraries)

  foreach( file ${addparalleltest_SOURCES} )
    get_filename_component( testname ${file} NAME_WE )
    if( lverbose )
      message( "   add_executable( Ut_${compname}_${testname}_exe ${file} )
   set_target_properties( Ut_${compname}_${testname}_exe PROPERTIES
      OUTPUT_NAME ${testname}
      VS_KEYWORD  ${testname}
      FOLDER      ${compname}_test
      COMPILE_DEFINITIONS \"PROJECT_SOURCE_DIR=\"${PROJECT_SOURCE_DIR}\";PROJECT_BINARY_DIR=\"${PROJECT_BINARY_DIR}\"\"
      ${Draco_std_target_props} )
      ")
    endif()
    add_executable( Ut_${compname}_${testname}_exe ${file} )
    dbs_std_tgt_props( Ut_${compname}_${testname}_exe )
    set_target_properties( Ut_${compname}_${testname}_exe PROPERTIES
      OUTPUT_NAME ${testname}
      VS_KEYWORD  ${testname}
      FOLDER      ${compname}_test
      COMPILE_DEFINITIONS "PROJECT_SOURCE_DIR=\"${PROJECT_SOURCE_DIR}\";PROJECT_BINARY_DIR=\"${PROJECT_BINARY_DIR}\"" )
    if( DEFINED DRACO_LINK_OPTIONS AND
        NOT "${DRACO_LINK_OPTIONS}x" STREQUAL "x" )
      set_target_properties( Ut_${compname}_${testname}_exe PROPERTIES
        LINK_OPTIONS ${DRACO_LINK_OPTIONS} )
    endif()
    if( addparalleltest_MPI_PLUS_OMP )
      if( ${CMAKE_GENERATOR} MATCHES Xcode )
        set_target_properties( Ut_${compname}_${testname}_exe
          PROPERTIES XCODE_ATTRIBUTE_ENABLE_OPENMP_SUPPORT YES )
      endif()
    endif()
    # Do we need to use the Fortran compiler as the linker?
    if( addparalleltest_LINK_WITH_FORTRAN )
      set_target_properties( Ut_${compname}_${testname}_exe
        PROPERTIES LINKER_LANGUAGE Fortran )
    endif()

    if( lverbose )
      message( "    target_link_libraries(
      Ut_${compname}_${testname}_exe
      ${test_lib_target_name}
      ${addparalleltest_DEPS} )")
    endif()
    target_link_libraries(
      Ut_${compname}_${testname}_exe
      ${test_lib_target_name}
      ${addparalleltest_DEPS} )

  endforeach()

  # 3. Register the unit test
  # 4. Register the pass/fail criteria.
  if( ${DRACO_C4} MATCHES "MPI" )
    foreach( file ${addparalleltest_SOURCES} )
      get_filename_component( testname ${file} NAME_WE )
      foreach( numPE ${addparalleltest_PE_LIST} )
        set( iarg 0 )
        if( "${addparalleltest_TEST_ARGS}none" STREQUAL "none" )
          register_parallel_test(
            ${compname}_${testname}_${numPE}
            ${numPE}
            $<TARGET_FILE:Ut_${compname}_${testname}_exe>
            "" )
        else()
          foreach( cmdarg ${addparalleltest_TEST_ARGS} )
            math( EXPR iarg "${iarg} + 1" )
            register_parallel_test(
              ${compname}_${testname}_${numPE}_arg${iarg}
              ${numPE}
              $<TARGET_FILE:Ut_${compname}_${testname}_exe>
              ${cmdarg} )
          endforeach()
        endif()
      endforeach()
    endforeach()
  else()
    # DRACO_C4=SCALAR Mode:
    foreach( file ${addparalleltest_SOURCES} )
      set( iarg "0" )
      get_filename_component( testname ${file} NAME_WE )

      set( addscalartest_PASS_REGEX "${addparalleltest_PASS_REGEX}" )
      set( addscalartest_FAIL_REGEX "${addparalleltest_FAIL_REGEX}" )
      set( addscalartest_RESOURCE_LOCK "${addparalleltest_RESOURCE_LOCK}" )
      set( addscalartest_RUN_AFTER "${addparalleltest_RUN_AFTER}" )

      if( "${addparalleltest_TEST_ARGS}none" STREQUAL "none" )
        if( lverbose )
          message("   register_scalar_test( ${compname}_${testname}
          \"${RUN_CMD}\" $<TARGET_FILE:Ut_${compname}_${testname}_exe> \"\" )")
        endif()
        register_scalar_test( ${compname}_${testname}
          "${RUN_CMD}" $<TARGET_FILE:Ut_${compname}_${testname}_exe> "" )
      else()

        foreach( cmdarg ${addparalleltest_TEST_ARGS} )
          math( EXPR iarg "${iarg} + 1" )
          if( lverbose )
            message("   register_scalar_test( ${compname}_${testname}_arg${iarg}
            \"${RUN_CMD}\" ${testname} \"${cmdarg}\" ) ")
            endif()
          register_scalar_test( ${compname}_${testname}_arg${iarg}
            "${RUN_CMD}" $<TARGET_FILE:Ut_${compname}_${testname}_exe> "${cmdarg}" )
        endforeach()

      endif()

    endforeach()
  endif()

  unset( lverbose )
endmacro()

#--------------------------------------------------------------------------------------------------#
# provide_aux_files
#
# Call this macro from a package CMakeLists.txt to instruct the build system
# that some files should be copied from the source directory into the build
# directory.
# ------------------------------------------------------------------------------#
macro( provide_aux_files )

  cmake_parse_arguments(
    auxfiles
    "NONE"
    "SRC_EXT;DEST_EXT;FOLDER"
    "FILES;TARGETS"
    ${ARGV}
    )

  unset(required_files)
  foreach( file ${auxfiles_FILES} )
    get_filename_component( srcfilenameonly ${file} NAME )
    if( auxfiles_SRC_EXT )
      if( auxfiles_DEST_EXT )
        # replace SRC_EXT with DEST_EXT
        string( REPLACE "${auxfiles_SRC_EXT}" "${auxfiles_DEST_EXT}"
          srcfilenameonly "${srcfilenameonly}" )
      else()
        # strip SRC_EXT
        string( REPLACE ${auxfiles_SRC_EXT} "" srcfilenameonly
          ${srcfilenameonly} )
      endif()
    else()
      if( auxfiles_DEST_EXT )
        # add DEST_EXT
        set( srcfilenameonly "${srcfilenameonly}${auxfiles_DEST_EXT}" )
      endif()
    endif()
    set( outfile ${PROJECT_BINARY_DIR}/${srcfilenameonly} )
    if( "${file}x" STREQUAL "x" OR "${outfile}x" STREQUAL "x")
    message( FATAL_ERROR " COMMAND ${CMAKE_COMMAND} -E copy_if_different ${file} ${outfile}")
    endif()
    add_custom_command(
      OUTPUT  ${outfile}
      COMMAND ${CMAKE_COMMAND} -E copy_if_different ${file} ${outfile}
      DEPENDS ${file}
      COMMENT "Copying ${file} to ${outfile}"
      )
    list( APPEND required_files "${outfile}" )
  endforeach()
  string( REPLACE "_test" "" compname ${PROJECT_NAME} )

  # Extra logic if multiple calls from the same directory.
  if( DEFINED Ut_${compname}_install_inputs_iarg )
    math( EXPR Ut_${compname}_install_inputs_iarg
      "${Ut_${compname}_install_inputs_iarg} + 1" )
  else()
    set( Ut_${compname}_install_inputs_iarg "0" CACHE INTERNAL
      "counter for each provide_aux_files command. Used to create individual
targets for copying support files.")
  endif()
  add_custom_target(
    Ut_${compname}_install_inputs_${Ut_${compname}_install_inputs_iarg}
    ALL
    DEPENDS ${required_files};${auxfiles_TARGETS}
    )
  if( auxfiles_FOLDER )
    set( folder_name ${auxfiles_FOLDER} )
  else()
    set( folder_name ${compname}_test )
  endif()
  set_target_properties(
    Ut_${compname}_install_inputs_${Ut_${compname}_install_inputs_iarg}
    PROPERTIES FOLDER ${folder_name} )

endmacro()

#--------------------------------------------------------------------------------------------------#
# PROCESS_AUTODOC_PAGES - Run configure_file(...) for all .dcc.in files found in
# the autodoc directory.  Destination will be the autodoc directory in the
# component binary directory.  The CMakeLists.txt in the draco/autodoc directory
# knows how to find these files.
#
# This allows CMAKE variables to be inserted into the .dcc files (e.g.:
# @Draco_VERSION@)
#
# E.g.: process_autodoc_pages()
#--------------------------------------------------------------------------------------------------#
macro( process_autodoc_pages )
  file( GLOB autodoc_in autodoc/*.in )
  foreach( file ${autodoc_in} )
    get_filename_component( dest_file ${file} NAME_WE )
    configure_file( ${file} ${PROJECT_BINARY_DIR}/autodoc/${dest_file}.dcc
      @ONLY )
  endforeach()
  file( GLOB images_in autodoc/*.jpg autodoc/*.png autodoc/*.gif )
  list( LENGTH images_in num_images )
  if( ${num_images} GREATER 0 )
    list( APPEND DOXYGEN_IMAGE_PATH "${PROJECT_SOURCE_DIR}/autodoc" )
  endif()
  set( DOXYGEN_IMAGE_PATH "${DOXYGEN_IMAGE_PATH}" CACHE PATH
     "List of directories that contain images for doxygen pages." FORCE )
  unset( images_in )
  unset( num_images )
endmacro()

#--------------------------------------------------------------------------------------------------#
# ADD_DIR_IF_EXISTS - A helper macro used for including sub-project directories
# from src/CMakeLists.
#--------------------------------------------------------------------------------------------------#
macro( add_dir_if_exists package )
  if( EXISTS ${PROJECT_SOURCE_DIR}/${package} )
    message( "   ${package}" )
    add_subdirectory( ${package} )
  endif()
endmacro()

#--------------------------------------------------------------------------------------------------#
# End config/component_macros.cmake
#--------------------------------------------------------------------------------------------------#
