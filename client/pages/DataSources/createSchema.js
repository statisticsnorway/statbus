import { array, number, object, string } from 'yup'

const createSchema = data => object({
  name: string().required().trim().default(data.name),
  description: string().default(data.description),
  allowedOperations: string().required().default(data.allowedOperations),
  attributesToCheck: array(string()).required().default(data.attributesToCheck),
  priority: number().required().default(data.priority),
  restrictions: number().required().default(data.restrictions),
  variablesMapping: string().required().default(data.variablesMapping),
})

export default createSchema
