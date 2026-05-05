project(reviews_tests)

set(SRC
        display_tests.cpp
        serdes_tests.cpp
)

omim_add_test(${PROJECT_NAME} ${SRC} NO_PLATFORM_INIT)

target_link_libraries(${PROJECT_NAME} reviews)
