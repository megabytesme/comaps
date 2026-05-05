project(reviews)

set(SRC
        display.hpp
        loader.cpp
        loader.hpp
        model.hpp
        serdes.hpp
)

omim_add_library(${PROJECT_NAME} ${SRC})

target_link_libraries(${PROJECT_NAME}
        base
        coding
        indexer
)

omim_add_test_subdirectory(reviews_tests)
