import React from 'react'
import { Segment, Select, Accordion, Icon } from 'semantic-ui-react'

import MappingsEditor from 'components/DataSourceMapper/'
import PlainTextField from 'components/fields/TextField'
import withDebounce from 'components/fields/withDebounce'
import { camelize } from 'helpers/camelCase'
import { bodyPropTypes } from 'helpers/formik'
import { meta } from '../model'
import * as propTypes from './propTypes'
import TemplateFileAttributesParser from './TemplateFileAttributesParser'
import styles from './styles.pcss'

const TextField = withDebounce(PlainTextField)

const FormBody = ({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  setValues,
  handleBlur,
  localize,
  columns,
}) => {
  const createProps = (key) => {
    const props = {
      ...meta.get(key),
      name: key,
      value: values[key],
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting,
      setFieldValue,
      onBlur: handleBlur,
      localize,
    }
    if (props.options) {
      props.options = meta.get(key).options.map(x => ({ ...x, text: localize(x.text) }))
    }
    return props
  }
  const activeColumns =
    columns[camelize(meta.statunitType.options.find(op => op.value === values.statUnitType).text)]
  return (
    <Segment>
      <TemplateFileAttributesParser onChange={setValues} localize={localize} />
      <Accordion className={styles['mappings-container']}>
        <Accordion.Title>
          <Icon name="dropdown" />
          {localize('VariablesMapping')}
        </Accordion.Title>
        <br />
        <Accordion.Content>
          <MappingsEditor
            name="variablesMapping"
            value={values.variablesMapping}
            onChange={(value) => { setFieldValue('variablesMapping', value) }}
            attributes={values.attributesToCheck}
            columns={activeColumns}
          />
        </Accordion.Content>
      </Accordion>
      <TextField {...createProps(meta.get('name'))} />
      <TextField {...createProps(meta.get('description'))} />
      <Select {...createProps(meta.get('allowedOperations'))} />
      <Select {...createProps(meta.get('priority'))} />
      <Select {...createProps(meta.get('statUnitType'))} />
    </Segment>
  )
}

FormBody.propTypes = {
  ...bodyPropTypes,
  values: propTypes.values.isRequired,
  columns: propTypes.columns.isRequired,
}

export default FormBody
