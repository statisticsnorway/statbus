import { array, number, object, string } from 'yup'

export default object({
  name: string().required().trim().default(''),
  description: string().default(''),
  allowedOperations: number().required().default(1),
  attributesToCheck: array(string()).required().default([]),
  priority: number().required().default(1),
  restrictions: number().required().default(1),
  variablesMapping: array(string()).required().default([]),
})
