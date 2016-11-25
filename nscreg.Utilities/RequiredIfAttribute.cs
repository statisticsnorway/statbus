using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Reflection;

namespace nscreg.Utilities
{
    public class RequiredIfAttribute : ValidationAttribute

    {
        private readonly RequiredAttribute _innerAttribute = new RequiredAttribute();

        public string DependentProperty { get; set; }
        public object[] TargetValues { get; set; }

        public RequiredIfAttribute(string dependentProperty, params object[] targetValues)
        {
            this.DependentProperty = dependentProperty;
            this.TargetValues = targetValues;
        }


        protected override ValidationResult IsValid(object value, ValidationContext validationContext)
        {
            var containerType = validationContext.ObjectInstance.GetType();
            var field = containerType.GetProperty(this.DependentProperty);

            if (field != null)
            {
                var dependentvalue = field.GetValue(validationContext.ObjectInstance, null);
                if ((dependentvalue == null && this.TargetValues == null) ||
                    (dependentvalue != null && TargetValues.Any(x => dependentvalue.Equals(this.TargetValues))))
                {
                    if (!_innerAttribute.IsValid(value))
                        return new ValidationResult(this.ErrorMessage, new[] { validationContext.MemberName });
                }
            }

            return null;
        }

    }
}
