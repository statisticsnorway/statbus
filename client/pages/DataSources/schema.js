import { array, number, object, string } from 'yup'

const schema = object({
  name: string().required(),
  description: string(),
  allowedOperations: string().required(),
  attributesToCheck: array(string()).required(),
  priority: number().required(),
  restrictions: string().required(),
  variablesMapping: string().required(),
})

export default schema
