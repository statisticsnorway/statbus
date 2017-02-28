import { object, string } from 'yup'

const createStatUnit = object({
  name: string().min(2).required('NameIsRequired'),
})

export default createStatUnit
