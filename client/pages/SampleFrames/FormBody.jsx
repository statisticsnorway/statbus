import React from 'react'
import PropTypes from 'prop-types'
import { Grid, Message, Tab } from 'semantic-ui-react'

import { formBody as bodyPropTypes } from 'components/createSchemaFormHoc/propTypes'
import PlainTextField from 'components/fields/TextField'
import withDebounce from 'components/fields/withDebounce'
import { hasValue } from 'helpers/validation'
import PredicateEditor from './PredicateEditor'
import FieldsEditor from './FieldsEditor'
import { predicate as predicatePropTypes } from './propTypes'

const TextField = withDebounce(PlainTextField)

const FormBody = ({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  handleBlur,
  localize,
}) => {
  const propsFor = key => ({
    name: key,
    value: values[key],
    touched: !!touched[key],
    errors: getFieldErrors(key),
    disabled: isSubmitting,
    setFieldValue,
    onBlur: handleBlur,
    localize,
  })
  const predicateProps = propsFor('predicate')
  const fieldsProps = propsFor('fields')
  return (
    <Grid>
      <Grid.Row>
        <Grid.Column width={6}>
          <TextField {...propsFor('name')} label="Name" placeholder="NameIsRequired" required />
        </Grid.Column>
      </Grid.Row>
      <Grid.Row
        as={Tab}
        panes={[
          {
            menuItem: localize('Predicate'),
            render: () => (
              <PredicateEditor
                value={values.predicate}
                onChange={value => setFieldValue('predicate', value)}
                localize={localize}
              />
            ),
          },
          {
            menuItem: localize('Fields'),
            render: () => (
              <FieldsEditor
                value={values.fields}
                onChange={value => setFieldValue('fields', value)}
                localize={localize}
              />
            ),
          },
        ]}
      />
      {hasValue(predicateProps.errors) && (
        <Message list={predicateProps.errors.map(localize)} error />
      )}
      {hasValue(fieldsProps.errors) && <Message list={fieldsProps.errors.map(localize)} error />}
    </Grid>
  )
}

const { arrayOf, number, shape, string } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shape({
    name: string.isRequired,
    fields: arrayOf(number).isRequired,
    predicate: predicatePropTypes.isRequired,
  }).isRequired,
}

export default FormBody
