import { array, number, object, string } from 'yup'

const schema = object({
  name: string().required().min(3).email('not a email'),
  description: string(),
  allowedOperations: string().required(),
  attributesToCheck: array(string()).required(),
  priority: number().required(),
  restrictions: string().required(),
  variablesMapping: string().required(),
})

export default schema
