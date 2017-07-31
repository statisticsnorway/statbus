import { array, number, object, string } from 'yup'

export default object({
  name: string().required().trim().default(''),
  description: string().default(''),
  restrictions: string().default(''),
  allowedOperations: number().required().default(1),
  attributesToCheck: array(string()).default([]),
  priority: number().required().default(1),
  statUnitType: number().required().default(1),
  variablesMapping: array(array(string())).required().default([]),
})
