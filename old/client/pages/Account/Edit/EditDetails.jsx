import React from 'react'
import PropTypes from 'prop-types'
import { Container, Header } from 'semantic-ui-react'

import { shapeOf } from '/helpers/validation'
import createSchemaFormHoc from '/components/createSchemaFormHoc'
import { schema, meta } from './model.js'
import FormBody from './FormBody.jsx'

const SchemaForm = createSchemaFormHoc(schema)(FormBody)

const EditDetails = ({ formData, submitAccount, navigateBack, localize }) => (
  <Container text>
    <Header as="h2">{localize('EditAccount')}</Header>
    <SchemaForm
      values={formData}
      onSubmit={submitAccount}
      onCancel={navigateBack}
      localize={localize}
    />
  </Container>
)

const { func, string } = PropTypes
EditDetails.propTypes = {
  formData: shapeOf([...meta.keys()])(string).isRequired,
  submitAccount: func.isRequired,
  navigateBack: func.isRequired,
  localize: func.isRequired,
}

export default EditDetails
