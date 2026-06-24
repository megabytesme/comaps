#include "categories_holder.hpp"

#include "coding/reader.hpp"

#include "platform/platform.hpp"

#include "defines.hpp"

#include <string>

extern void MwmCoreTrace(std::string const & message);

CategoriesHolder const & GetDefaultCategories()
{
  static CategoriesHolder const instance([]()
  {
    MwmCoreTrace("Categories loader reader begin");
    auto reader = GetPlatform().GetReader(SEARCH_CATEGORIES_FILE_NAME);
    MwmCoreTrace("Categories loader reader complete bytes=" + std::to_string(reader->Size()));
    return CategoriesHolder(std::move(reader));
  }());
  MwmCoreTrace("Categories loader complete");
  return instance;
}
