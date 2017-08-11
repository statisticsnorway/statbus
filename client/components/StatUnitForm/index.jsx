import { Formik } from 'formik'

import StatUnitForm from './StatUnitForm'

// statUnit: shape({
//   id: number,
//   properties: arrayOf(shape({
//     value: any,
//     selector: number,
//     name: string,
//   })).isRequired,
//   statUnitType: number,
//   dataAccess: arrayOf(string).isRequired,
// }).isRequired,

// const options = {
//   displayName: 'StatUnitSchemaForm',
//   isInitialValid: false,
//   mapPropsToValues: props => props,
//   validationSchema: schema,
//   handleSubmit: (values, formikBag) => {},
// }

// TODO: update usage of this form (where to define options?)
export default options => Formik(options)(StatUnitForm)
