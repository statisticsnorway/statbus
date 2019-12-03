using System;
using System.Collections.Generic;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Base class for view model
    /// </summary>
    public class ViewModelBase
    {
        public IEnumerable<PropertyMetadataBase> Properties { get; set; } = Array.Empty<PropertyMetadataBase>();
    }
}
