using nscreg.Utilities.Enums;

namespace nscreg.ModelGeneration.Validation
{
    public interface IValidationEndpointProvider
    {
        string Get(ValidationTypeEnum? validationType);
    }
}
