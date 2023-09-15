import React, { useState, useEffect } from 'react'
import PropTypes from 'prop-types'
import { Button, Table, Form, Popup } from 'semantic-ui-react'
import R from 'ramda'
import config from '/client/helpers/config'
import { activityTypes } from '/client/helpers/enums'
import { DateTimeField, SelectField } from '/client/components/fields'
import { getNewName } from '../../../helpers/locale'

const activities = [...activityTypes].map(([key, value]) => ({ key, value }))
const yearsOptions = [...Array(new Date().getFullYear() - 1899).keys()].map(x => ({
  value: x + 1900,
  text: (x + 1900).toString(),
}))

const ActivityCode = ({ 'data-name': name, 'data-code': code }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name != null && name.length > 50 ? (
      <span title={name}>{`${name.substring(0, 50)}...`}</span>
    ) : (
      <span>{name}</span>
    )}
  </span>
)

ActivityCode.propTypes = {
  'data-name': PropTypes.string.isRequired,
  'data-code': PropTypes.string.isRequired,
}

function ActivityEdit(props) {
  const { onSave, onCancel, localize, locale, disabled, index, value: initialValue } = props

  const activityMandatoryFields = config.mandatoryFields.Activity
  const [value, setValue] = useState(initialValue)
  const [touched, setTouched] = useState(false)
  const [isLoading, setIsLoading] = useState(false)

  useEffect(() => {
    if (props.locale !== locale) {
      setValue({
        ...value,
        value: value.id,
        label: getNewName(value),
      })
    }
  }, [props.locale, locale, value])

  const employeesIsNaN = isNaN(parseInt(value.employees, 10))
  const notSelected = { value: 0, text: localize('NotSelected') }

  const onFieldChange = (e, { name, value }) => {
    setValue(prevValue => ({
      ...prevValue,
      [name]: value,
    }))
    setTouched(true)
  }

  const onCodeChange = (e, { value }) => {
    setValue(prevValue => ({
      ...prevValue,
      activityCategoryId: {
        id: undefined,
        code: value,
        name: '',
      },
    }))
    setIsLoading(true)
    searchData(value)
  }

  const saveHandler = () => {
    onSave(value, index)
  }

  const cancelHandler = () => {
    onCancel(value.id)
  }

  const activitySelectedHandler = (e, { value: activityCategoryId }, activityCategory) => {
    setValue(prevValue => ({
      ...prevValue,
      activityCategoryId,
      activityCategory,
    }))
    setTouched(true)
  }

  return (
    <Table.Row>
      <Table.Cell colSpan={8}>
        <Form as="div">
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('ActivityCategoryIdTooltip')}
              data-position="top left"
            >
              <SelectField
                name="activityCategoryId"
                label="StatUnitActivityRevX"
                lookup={13}
                onChange={activitySelectedHandler}
                value={value.activityCategoryId}
                localize={localize}
                locale={locale}
                required={activityMandatoryFields.ActivityCategoryId}
              />
            </div>
          </Form.Group>
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('StatUnitActivityTypeTooltip')}
              data-position="top left"
            >
              <Form.Select
                label={localize('StatUnitActivityType')}
                placeholder={localize('StatUnitActivityType')}
                options={activities.map(a => ({
                  value: a.key,
                  text: localize(a.value),
                }))}
                value={value.activityType}
                error={!value.activityType}
                name="activityType"
                onChange={onFieldChange}
                disabled={disabled}
                required={activityMandatoryFields.ActivityType}
              />
            </div>
            <div
              className="field"
              data-tooltip={localize('ActivityYearTooltip')}
              data-position="top left"
            >
              <Form.Select
                label={localize('ActivityYear')}
                placeholder={localize('ActivityYear')}
                options={[notSelected, ...yearsOptions]}
                value={value.activityYear}
                name="activityYear"
                onChange={onFieldChange}
                disabled={disabled}
                required={activityMandatoryFields.ActivityYear}
                search
              />
            </div>
          </Form.Group>
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('StatUnitActivityEmployeesNumberTooltip')}
              data-position="top left"
            >
              <Popup
                trigger={
                  <Form.Input
                    label={localize('StatUnitActivityEmployeesNumber')}
                    placeholder={localize('StatUnitActivityEmployeesNumber')}
                    type="number"
                    name="employees"
                    value={value.employees}
                    onChange={onFieldChange}
                    min={0}
                    required={activityMandatoryFields.Employees}
                    disabled={disabled}
                    autoComplete="off"
                  />
                }
                content={`6 ${localize('MaxLength')}`}
                open={value.employees != null && value.employees.length > 6}
              />
            </div>
            <div
              data-tooltip={localize('InThousandsKGS')}
              data-position="top left"
              className="field"
            >
              <Popup
                trigger={
                  <Form.Input
                    label={localize('Turnover')}
                    placeholder={localize('Turnover')}
                    name="turnover"
                    type="number"
                    value={value.turnover}
                    onChange={onFieldChange}
                    min={0}
                    disabled={disabled}
                    required={activityMandatoryFields.Turnover}
                    autoComplete="off"
                  />
                }
                content={`10 ${localize('MaxLength')}`}
                open={value.turnover != null && value.turnover.length > 10}
              />
            </div>
          </Form.Group>
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('StatUnitActivityDateTooltip')}
              data-position="top left"
            >
              <DateTimeField
                value={value.idDate}
                onChange={onFieldChange}
                name="idDate"
                label="StatUnitActivityDate"
                disabled={disabled}
                localize={localize}
                required={activityMandatoryFields.IdDate}
              />
            </div>
            <div className="field right aligned">
              <label htmlFor="saveBtn">&nbsp;</label>
              <Button.Group>
                <div data-tooltip={localize('ButtonSave')} data-position="top center">
                  <Button
                    id="saveBtn"
                    icon="check"
                    color="green"
                    onClick={saveHandler}
                    disabled={
                      disabled ||
                      (activityMandatoryFields.Employees &&
                        value.employees != null && value.employees.length > 6) ||
                      (value.turnover != null && value.turnover.length > 10) ||
                      (activityMandatoryFields.ActivityCategoryId && !value.activityCategoryId) ||
                      (activityMandatoryFields.ActivityType && !value.activityType) ||
                      (activityMandatoryFields.ActivityYear && !value.activityYear) ||
                      (activityMandatoryFields.Employees && !value.employees && employeesIsNaN) ||
                      (activityMandatoryFields.Turnover && !value.turnover) ||
                      (activityMandatoryFields.IdDate && !value.idDate) ||
                      !touched
                    }
                  />
                </div>
                <div data-tooltip={localize('ButtonCancel')} data-position="top center">
                  <Button
                    type="button"
                    icon="cancel"
                    color="red"
                    onClick={cancelHandler}
                    disabled={disabled}
                  />
                </div>
              </Button.Group>
            </div>
          </Form.Group>
        </Form>
      </Table.Cell>
    </Table.Row>
  )
}

ActivityEdit.propTypes = {
  onSave: PropTypes.func.isRequired,
  onCancel: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
  locale: PropTypes.string.isRequired,
  disabled: PropTypes.bool,
  index: PropTypes.number,
  value: PropTypes.shape({
    id: PropTypes.number,
    activityYear: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    activityType: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    employees: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    turnover: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    activityCategoryId: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
  }).isRequired,
}

ActivityEdit.defaultProps = {
  disabled: false,
  value: null,
}

export default ActivityEdit
