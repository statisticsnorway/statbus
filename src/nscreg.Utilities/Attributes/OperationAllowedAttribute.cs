using System;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Utilities.Attributes
{
    public class OperationAllowedAttribute : Attribute
    {
        public OperationAllowedAttribute(params OperationEnum[] allowedOps)
        {
            AllowedOperations = allowedOps;
        }

        public OperationEnum[] AllowedOperations { get; }
    }
}
