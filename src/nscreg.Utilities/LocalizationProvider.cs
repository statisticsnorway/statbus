using System;
using System.Collections.Generic;
using System.Resources;
using System.Text;
using nscreg.Resources.Languages;

namespace nscreg.Utilities
{
    public class LocalizationProvider
    {
        private readonly ResourceManager _resourceManager;

        public LocalizationProvider()
        {
            _resourceManager = new ResourceManager(typeof(Resource));
        }

        public string GetString(string key)
        {
            return _resourceManager.GetString(key);
        }
    }
}
