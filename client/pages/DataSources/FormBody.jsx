import React, { useState } from 'react'
import PropTypes from 'prop-types'
import { Grid, Form } from 'semantic-ui-react'

import {
  SelectField as PlainSelectField,
  TextField as PlainTextField,
  withDebounce,
} from 'components/fields'
import { getMandatoryFields as getMandatoryFieldsForStatUnitUpload } from 'helpers/config'
import handlerFor from 'helpers/handleSetFieldValue'
import { toCamelCase } from 'helpers/string'
import MappingEditor from './MappingEditor'
import TemplateFileAttributesParser from './TemplateFileAttributesParser'
import { meta, getMandatoryFieldsForActivityUpload, getFieldsForActivityUpload } from './model'
import styles from './styles.pcss'

const getTypeName = value =>
  toCamelCase(meta.get('statUnitType').options.find(op => op.value === value).text)

const variablesForActivities = getFieldsForActivityUpload()

const { Column } = Grid
const { Group } = Form
const TextField = withDebounce(PlainTextField)
const SelectField = withDebounce(PlainSelectField)

function FormBody({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  setValues,
  handleBlur,
  localize,
  columns,
  location: { pathname },
}) {
  const [mapping, attribs] = [createProps('variablesMapping'), createProps('attributesToCheck')]

  const createProps = (key) => {
    const props = {
      ...meta.get(key),
      name: key,
      value: values[key],
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting,
      onChange: handlerFor(setFieldValue),
      onBlur: handleBlur,
      localize,
      url: pathname,
    }
    if (props.options) {
      props.options = props.options.map(x => ({
        ...x,
        text: localize(x.text),
      }))
    }
    return props
  }

  const updateValues = data => setValues({ ...values, ...data })

  const columnsByUnitType = columns[getTypeName(values.statUnitType)]
  const filteredColumnsForActivities = columnsByUnitType.filter(el => variablesForActivities.filter(varForAc => varForAc === el.name).length === 1)

  return (
    <Grid>
      <Grid.Row>
        <Column width={6}>
          <TemplateFileAttributesParser
            csvDelimiter={values.csvDelimiter}
            csvSkipCount={values.csvSkipCount}
            onChange={updateValues}
            localize={localize}
          />
        </Column>
        <Column width={10}>
          <TextField {...createProps('name')} width={8} />
          <TextField {...createProps('description')} width={12} />
          <SelectField {...createProps('dataSourceUploadType')} />
          <Group widths="equal">
            <SelectField {...createProps('allowedOperations')} />
            <SelectField {...createProps('priority')} />
            <SelectField {...createProps('statUnitType')} />
          </Group>
        </Column>
      </Grid.Row>
      <Grid.Row>
        <Column className={styles['mappings-container']} width={16}>
          <MappingEditor
            name="variablesMapping"
            value={values.variablesMapping}
            onChange={value => setFieldValue('variablesMapping', value)}
            attributes={values.attributesToCheck}
            columns={
              values.dataSourceUploadType === 1 ? columnsByUnitType : filteredColumnsForActivities
            }
            mandatoryColumns={
              values.dataSourceUploadType === 1
                ? getMandatoryFieldsForStatUnitUpload(values.statUnitType)
                : getMandatoryFieldsForActivityUpload()
            }
            localize={localize}
            mapping={mapping}
            attribs={attribs}
            isUpdate={values.allowedOperations === 2}
          />
        </Column>
      </Grid.Row>
    </Grid>
  )
}

FormBody.propTypes = {
  values: PropTypes.shape({
    name: PropTypes.string.isRequired,
    description: PropTypes.string.isRequired,
    allowedOperations: PropTypes.number.isRequired,
    priority: PropTypes.number.isRequired,
    statUnitType: PropTypes.number.isRequired,
    attributesToCheck: PropTypes.arrayOf(PropTypes.string).isRequired,
    variablesMapping: PropTypes.arrayOf(PropTypes.arrayOf(PropTypes.string)).isRequired,
    csvDelimiter: PropTypes.string.isRequired,
    csvSkipCount: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
  }).isRequired,
  getFieldErrors: PropTypes.func.isRequired,
  touched: PropTypes.object.isRequired,
  isSubmitting: PropTypes.bool.isRequired,
  setFieldValue: PropTypes.func.isRequired,
  setValues: PropTypes.func.isRequired,
  handleBlur: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
  columns: PropTypes.shape({
    localUnit: PropTypes.arrayOf(PropTypes.shape({ name: PropTypes.string })),
    legalUnit: PropTypes.arrayOf(PropTypes.shape({ name: PropTypes.string })),
    enterpriseUnit: PropTypes.arrayOf(PropTypes.shape({ name: PropTypes.string })),
  }).isRequired,
  location: PropTypes.shape({ pathname: PropTypes.string }),
}

FormBody.defaultProps = {
  location: { pathname: '' },
}

export default FormBody
