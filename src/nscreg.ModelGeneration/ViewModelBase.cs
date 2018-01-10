using System;
using System.Collections.Generic;

namespace nscreg.ModelGeneration
{
    /// <summary>
    /// Базовый класс для вью модели
    /// </summary>
    public class ViewModelBase
    {
        public IEnumerable<PropertyMetadataBase> Properties { get; set; } = Array.Empty<PropertyMetadataBase>();
    }
}
