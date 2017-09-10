import { array, number, object, string } from 'yup'

export default object({
  name: string().required().trim().max(20).default(''),
  description: string().max(30).default(''),
  restrictions: string().max(30).default(''),
  allowedOperations: number().required().default(1),
  attributesToCheck: array(string()).default([]),
  priority: number().required().default(1),
  statUnitType: number().required().default(1),
  variablesMapping: array(array(string())).required().default([]),
})
